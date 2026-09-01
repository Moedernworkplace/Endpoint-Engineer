<#
    Shared, parameterized printer install script - matches the pattern already
    proven working across 92 devices for "Printer 45 - Accounting latest".

    Assumes the printer driver is already staged (e.g. via the separate
    "Xerox Phaser 3330 PCL6 Driver" app). Only creates the TCP/IP port and the
    printer queue itself. Falls back to staging the driver from a bundled INF
    only if it isn't already present - this keeps the package tiny in the
    normal case.
#>

param(
    [Parameter(Mandatory = $true)][string]$PortName,
    [Parameter(Mandatory = $true)][string]$PrinterIP,
    [Parameter(Mandatory = $true)][string]$PrinterName,
    [Parameter(Mandatory = $true)][string]$DriverName,
    [string]$INFFile
)

$ErrorActionPreference = "Stop"

try {
    if (-not (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)) {
        Write-Output "Driver '$DriverName' not found on this device."
        if ($INFFile) {
            $infPath = Join-Path $PSScriptRoot $INFFile
            if (Test-Path $infPath) {
                Write-Output "Staging driver from bundled INF: $infPath ..."
                pnputil /add-driver "$infPath" /install | Out-Null
                Add-PrinterDriver -Name $DriverName
            } else {
                throw "Driver '$DriverName' is missing and no bundled INF was found at $infPath."
            }
        } else {
            throw "Driver '$DriverName' is missing and no INF file was provided to stage it."
        }
    } else {
        Write-Output "Driver '$DriverName' already present."
    }

    if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
        Write-Output "Creating TCP/IP port $PortName -> $PrinterIP ..."
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
    } else {
        $existingPort = Get-PrinterPort -Name $PortName
        if ($existingPort.PrinterHostAddress -ne $PrinterIP) {
            Write-Output "Updating port $PortName IP from $($existingPort.PrinterHostAddress) to $PrinterIP ..."
            Set-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
        } else {
            Write-Output "Port $PortName already exists with the correct IP."
        }
    }

    if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
        Write-Output "Adding printer '$PrinterName' ..."
        Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName
    } else {
        Write-Output "Printer '$PrinterName' already exists."
    }

    Write-Output "Install complete for $PrinterName."
    exit 0
}
catch {
    Write-Error "Install failed for $PrinterName : $_"
    exit 1
}
