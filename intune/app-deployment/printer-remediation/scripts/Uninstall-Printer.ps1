<#
    Shared, parameterized printer uninstall script - matches "Printer 45 -
    Accounting latest"'s pattern. Removes just the printer queue.
#>

param(
    [Parameter(Mandatory = $true)][string]$PrinterName
)

$ErrorActionPreference = "SilentlyContinue"

Remove-Printer -Name $PrinterName

Write-Output "Removed $PrinterName."
exit 0
