<#
    Lists the current members (devices/users) of every "Printer <name>" Entra ID
    group, so you can see at a glance who/what is assigned to each printer.
#>

[CmdletBinding()]
param(
    [string]$GroupsCsvPath = ".\printer_groups.csv"
)

if (-not (Test-Path $GroupsCsvPath)) {
    Write-Error "Groups CSV not found at $GroupsCsvPath"
    exit 1
}

$rows = Import-Csv -Path $GroupsCsvPath

Write-Output "Connecting to Microsoft Graph ..."
Connect-MgGraph -Scopes "Group.Read.All", "Directory.Read.All" -NoWelcome

$results = @()

foreach ($row in $rows) {
    $printerName = $row.PrinterName
    $groupName   = "Printer $printerName"

    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue

    if (-not $group) {
        Write-Warning "Group '$groupName' not found - skipping."
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; MemberName = "(group not found)"; MemberType = "" }
        continue
    }

    $members = Get-MgGroupMember -GroupId $group.Id -All

    if (-not $members -or $members.Count -eq 0) {
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; MemberName = "(empty - no members yet)"; MemberType = "" }
        continue
    }

    foreach ($member in $members) {
        $displayName = $member.AdditionalProperties.displayName
        $odataType   = $member.AdditionalProperties.'@odata.type' -replace '#microsoft.graph.', ''
        $results += [PSCustomObject]@{ PrinterName = $printerName; GroupName = $groupName; MemberName = $displayName; MemberType = $odataType }
    }
}

Write-Output "`n===== Group Membership ====="
$results | Format-Table -AutoSize

$results | Export-Csv -Path ".\printer_group_membership.csv" -NoTypeInformation
Write-Output "`nSaved to .\printer_group_membership.csv"
