<#
    Bulk-creates one empty Entra ID security group per printer, named after the printer's
    hostname, with the printer's IP address in the group description. No members added.

    Simplified version - no user/device lookups. Reads printer_groups.csv (PrinterName, IPAddress)
    and for each row creates a group named "Printer <PrinterName>" (matching the naming convention
    already used for the manually-created "Printer 14-05" group), with a description that includes
    the IP address for reference. If a group with that name already exists, it's left alone and
    reported as already-existing rather than duplicated.

    Add members (users or devices) yourself afterward in the portal, or extend the mapping CSV
    later once device/user data is sorted out.
#>

[CmdletBinding()]
param(
    [string]$GroupsCsvPath = ".\printer_groups.csv",
    [switch]$WhatIf
)

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
    Write-Error "Microsoft.Graph.Groups module not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser"
    exit 1
}

if (-not (Test-Path $GroupsCsvPath)) {
    Write-Error "Groups CSV not found at $GroupsCsvPath"
    exit 1
}

$rows = Import-Csv -Path $GroupsCsvPath

Write-Output "Connecting to Microsoft Graph ..."
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Directory.Read.All" -NoWelcome

$results = @()

foreach ($row in $rows) {
    $printerName = $row.PrinterName
    $ip          = $row.IPAddress
    $groupName   = "Printer $printerName"
    $description = "Assignment group for printer $printerName (IP: $ip). Add members manually."

    Write-Output "`n--- $groupName ---"

    $existingGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

    if ($existingGroup) {
        Write-Output "Already exists (Id: $($existingGroup.Id)) - skipping creation."
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; Status = "Already existed"; GroupId = $existingGroup.Id }
        continue
    }

    if ($WhatIf) {
        Write-Output "[WHATIF] Would create group '$groupName' with description: $description"
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; Status = "WHATIF - would create"; GroupId = $null }
        continue
    }

    try {
        $mailNickname = ($groupName -replace '[^a-zA-Z0-9\-]', '')
        $group = New-MgGroup -DisplayName $groupName -Description $description `
            -MailEnabled:$false -MailNickname $mailNickname -SecurityEnabled:$true -GroupTypes @()

        Write-Output "OK: created '$groupName' (Id: $($group.Id))"
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; Status = "Created"; GroupId = $group.Id }
    }
    catch {
        Write-Warning "FAILED creating '$groupName' : $_"
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; Status = "FAILED - $_"; GroupId = $null }
    }
}

Write-Output "`n===== Summary ====="
$results | Format-Table -AutoSize

$results | Export-Csv -Path ".\printer_group_results.csv" -NoTypeInformation
Write-Output "`nSaved to .\printer_group_results.csv - use GroupId with Upload-IntunewinApps.ps1 -AssignGroupId once you've added members."
