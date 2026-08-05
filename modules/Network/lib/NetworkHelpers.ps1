# Network helpers
function Format-DnsList {
    param([string[]]$Servers)
    if (-not $Servers -or $Servers.Count -eq 0) { return "-" }
    return ($Servers -join ", ")
}
