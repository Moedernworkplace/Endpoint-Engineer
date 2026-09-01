<#
.SYNOPSIS
    Creates Intune Win32 apps for printers using the ONE shared Install-Printer.intunewin
    package, with per-printer command-line parameters and registry-based detection.
    This matches the confirmed-working config for "Printer - 14-17" and "Printer - 14-20".

.DESCRIPTION
    Reads printers.csv (PrinterName, DriverName, DriverInfPath, IPAddress, PortName) and,
    for each row not already created, calls Add-IntuneWin32App using the shared
    Install-Printer.intunewin package with -InstallCommandLine / -UninstallCommandLine
    built from that row's values, plus a registry "key exists" detection rule at
    HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Print\Printers\<PrinterName>.

    Requires the IntuneWin32App PowerShell module:
        Install-Module -Name IntuneWin32App -Scope CurrentUser -Force

.PARAMETER TenantID
    Use the tenant's actual Tenant ID GUID (from Entra admin center -> Overview), NOT the
    vanity domain - this avoids Windows SSO cached-account routing to the wrong tenant.

.PARAMETER ClientID
    Your Entra App Registration's Application (client) ID.

.PARAMETER SharedPackagePath
    Path to the shared Install-Printer.intunewin file.

.PARAMETER CsvPath
    Path to printers.csv (default .\printers.csv)

.PARAMETER OnlyApp
    Optional. Restrict this run to one printer name (e.g. "14-19") to test before batching.

.PARAMETER GroupResultsCsvPath
    Path to printer_group_results.csv (PrinterName -> GroupId), for auto-assignment.
    Default .\printer_group_results.csv

.EXAMPLE
    .\Upload-SharedPrinterApps.ps1 -TenantID "<tenant GUID>" -ClientID "<client ID>" -OnlyApp "14-19"

.EXAMPLE
    .\Upload-SharedPrinterApps.ps1 -TenantID "<tenant GUID>" -ClientID "<client ID>"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantID,

    [Parameter(Mandatory = $true)]
    [string]$ClientID,

    [string]$SharedPackagePath = ".\IntunewinOutput\Install-Printer.intunewin",
    [string]$CsvPath = ".\printers.csv",
    [string]$OnlyApp,
    [string]$Publisher = "IT - Printers",
    [string]$GroupResultsCsvPath = ".\printer_group_results.csv",

    # Printers already built manually (14-17, 14-19, 14-20, and Printer44-Design/45/47/48)
    # - skipped by default so this script never tries to duplicate them.
    # 45/47/48 also use different drivers entirely (AltaLink/HP), not the shared Phaser
    # 3330 package, so they'd be built wrong if this script ever touched them anyway.
    # Override with -SkipNames @() if you explicitly want to include some of them.
    [string[]]$SkipNames = @("14-17", "14-20", "14-19", "Printer44-Design", "Printer 45 - Accounting", "Printer 47 - Business", "Printer 48 - Reception")
)

if (-not (Test-Path $SharedPackagePath)) {
    Write-Error "Shared package not found at $SharedPackagePath"
    exit 1
}

# Add-IntuneWin32App's internal metadata reader has a known quirk where it
# resolves relative paths against the wrong base directory. Always hand it
# a fully-resolved absolute path to avoid "Could not find a part of the path" errors.
$SharedPackagePath = (Resolve-Path -Path $SharedPackagePath).Path
Write-Output "Using package: $SharedPackagePath"

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV not found at $CsvPath"
    exit 1
}

$rows = Import-Csv -Path $CsvPath
if ($OnlyApp) {
    $rows = $rows | Where-Object { $_.PrinterName -eq $OnlyApp }
    if ($rows.Count -eq 0) {
        Write-Error "No row found matching -OnlyApp '$OnlyApp' in $CsvPath"
        exit 1
    }
} else {
    $rows = $rows | Where-Object { $SkipNames -notcontains $_.PrinterName }
}

$groupLookup = @{}
if (Test-Path $GroupResultsCsvPath) {
    Write-Output "Loading per-printer group mapping from $GroupResultsCsvPath ..."
    Import-Csv -Path $GroupResultsCsvPath | ForEach-Object {
        if ($_.GroupId) { $groupLookup[$_.PrinterName] = $_.GroupId }
    }
}

if (-not (Get-Module -ListAvailable -Name IntuneWin32App)) {
    Write-Error "IntuneWin32App module not installed. Run: Install-Module -Name IntuneWin32App -Scope CurrentUser -Force"
    exit 1
}
Import-Module IntuneWin32App -ErrorAction Stop

Write-Output "Authenticating to Microsoft Graph ..."
Connect-MSIntuneGraph -TenantID $TenantID -ClientID $ClientID

$RequirementRule = New-IntuneWin32AppRequirementRule -Architecture "x64x86" -MinimumSupportedWindowsRelease "W10_1607"

$created = 0
$failed  = @()

foreach ($row in $rows) {
    $printerName = $row.PrinterName
    $ip          = $row.IPAddress
    $portName    = $row.PortName
    $driverName  = $row.DriverName
    $infFileName = Split-Path -Path $row.DriverInfPath -Leaf

    Write-Output "`n--- $printerName ---"

    try {
        $DisplayName          = "Printer - $printerName"
        $InstallCommandLine   = "powershell.exe -executionpolicy bypass -file .\Install-Printer.ps1 -PortName `"$portName`" -PrinterIP `"$ip`" -PrinterName `"$printerName`" -DriverName `"$driverName`" -INFFile `"$infFileName`""
        $UninstallCommandLine = "powershell.exe -executionpolicy bypass -file .\Uninstall-Printer.ps1 -PrinterName `"$printerName`""
        $RegistryKeyPath      = "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Print\Printers\$printerName"

        $DetectionRule = New-IntuneWin32AppDetectionRuleRegistry -Existence -KeyPath $RegistryKeyPath -DetectionType exists -Check32BitOn64System $false

        Write-Output "Creating Win32 app '$DisplayName' from $SharedPackagePath ..."
        $Win32App = Add-IntuneWin32App -FilePath $SharedPackagePath -DisplayName $DisplayName `
            -Description "Network printer deployment: $printerName" -Publisher $Publisher `
            -InstallExperience "system" -RestartBehavior "suppress" `
            -DetectionRule $DetectionRule -RequirementRule $RequirementRule `
            -InstallCommandLine $InstallCommandLine -UninstallCommandLine $UninstallCommandLine `
            -Verbose

        if (-not $Win32App -or -not $Win32App.id) {
            throw "Add-IntuneWin32App did not return a valid app object - app was not created, skipping assignment."
        }

        $targetGroupId = $null
        if ($groupLookup.ContainsKey($printerName)) {
            $targetGroupId = $groupLookup[$printerName]
        }

        if ($targetGroupId) {
            Write-Output "Assigning to group $targetGroupId (Required) ..."
            Add-IntuneWin32AppAssignmentGroup -Include -ID $Win32App.id -GroupID $targetGroupId -Intent "required" -Notification "showAll"
        } else {
            Write-Output "No matching group found for $printerName - app created unassigned. Assign manually in the portal."
        }

        Write-Output "OK: $DisplayName created (ID $($Win32App.id))"
        $created++
    }
    catch {
        Write-Warning "FAILED creating app for $printerName : $_"
        $failed += $printerName
    }
}

Write-Output "`n$created of $($rows.Count) apps created successfully."
if ($failed.Count -gt 0) {
    Write-Warning "Failed: $($failed -join ', ')"
}
