<#
    Adds one or more real, confirmed devices to each printer's existing Entra ID
    assignment group (e.g. "Printer 14-05"), by device name only - no user lookup.

    Reads printer_device_mapping.csv (PrinterName, AssignedUserEmail, DeviceNames).
    DeviceNames is a semicolon-separated list of Entra ID device display names
    (e.g. "US-WIN-BETCRE;AC-SURFACE" for a printer whose user has two machines
    that both need the driver). Rows with a blank DeviceNames column are skipped
    and reported - fill those in once you have the real hostname.

    For each device name, looks it up directly by displayName (exact match first,
    then startswith as a fallback for partial/typo'd names), and adds it to the
    "Printer <PrinterName>" group if not already a member. Never guesses - if a
    device name doesn't resolve to exactly one device, it's skipped and reported.
#>

[CmdletBinding()]
param(
    [string]$MappingCsvPath = ".\printer_device_mapping.csv",
    [switch]$WhatIf
)

if (-not (Test-Path $MappingCsvPath)) {
    Write-Error "Mapping CSV not found at $MappingCsvPath"
    exit 1
}

$rows = Import-Csv -Path $MappingCsvPath

Write-Output "Connecting to Microsoft Graph ..."
Connect-MgGraph -Scopes "Device.Read.All", "GroupMember.ReadWrite.All", "Group.Read.All" -NoWelcome

$results = @()

foreach ($row in $rows) {
    $printerName = $row.PrinterName
    $groupName   = "Printer $printerName"
    $deviceList  = $row.DeviceNames

    Write-Output "`n--- $printerName ($groupName) ---"

    if ([string]::IsNullOrWhiteSpace($deviceList)) {
        Write-Warning "SKIPPED: no DeviceNames listed for $printerName yet."
        $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $null; Status = "SKIPPED - no device name provided" }
        continue
    }

    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
    if (-not $group) {
        Write-Warning "SKIPPED: group '$groupName' not found in Entra ID. Run Create-PrinterGroups.ps1 first."
        $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $null; Status = "SKIPPED - group not found" }
        continue
    }

    $existingMembers = Get-MgGroupMember -GroupId $group.Id -All

    $deviceNames = $deviceList -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    foreach ($deviceName in $deviceNames) {
        $device = Get-MgDevice -Filter "displayName eq '$deviceName'" -ErrorAction SilentlyContinue

        if (-not $device) {
            $candidates = Get-MgDevice -Filter "startswith(displayName,'$deviceName')" -ErrorAction SilentlyContinue
            if ($candidates.Count -eq 1) {
                $device = $candidates
                Write-Output "No exact match for '$deviceName' - using close match '$($device.DisplayName)'."
            } elseif ($candidates.Count -gt 1) {
                $names = ($candidates | ForEach-Object { $_.DisplayName }) -join ", "
                Write-Warning "SKIPPED: '$deviceName' matched multiple devices ($names) - fix the name to be exact."
                $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $deviceName; Status = "SKIPPED - ambiguous match ($names)" }
                continue
            }
        }

        if (-not $device) {
            Write-Warning "SKIPPED: no device found in Entra ID matching '$deviceName'."
            $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $deviceName; Status = "SKIPPED - device not found" }
            continue
        }

        if ($existingMembers.Id -contains $device.Id) {
            Write-Output "'$($device.DisplayName)' already a member of '$groupName'."
            $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $device.DisplayName; Status = "Already a member" }
            continue
        }

        if ($WhatIf) {
            Write-Output "[WHATIF] Would add '$($device.DisplayName)' (Id: $($device.Id)) to '$groupName'."
            $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $device.DisplayName; Status = "WHATIF - would add" }
            continue
        }

        try {
            New-MgGroupMemberByRef -GroupId $group.Id -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($device.Id)" }
            Write-Output "OK: added '$($device.DisplayName)' to '$groupName'."
            $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $device.DisplayName; Status = "Added" }
        }
        catch {
            Write-Warning "FAILED adding '$deviceName' to '$groupName' : $_"
            $results += [PSCustomObject]@{ PrinterName = $printerName; DeviceName = $deviceName; Status = "FAILED - $_" }
        }
    }
}

Write-Output "`n===== Summary ====="
$results | Format-Table -AutoSize

$results | Export-Csv -Path ".\printer_device_group_results.csv" -NoTypeInformation
Write-Output "`nSaved to .\printer_device_group_results.csv"
