param(
    [ValidateSet("Balanced", "High", "Saver", "Custom")]
    [string]$Plan = "Balanced",
    [string]$Guid = ""
)
try {
    $map = @{
        Balanced = "381b4222-f694-41f0-9685-ff5bb260df2e"
        High     = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        Saver    = "a1841308-3541-4fab-bc81-f71556f20b4a"
    }
    $target = if ($Guid) { $Guid } elseif ($map.ContainsKey($Plan)) { $map[$Plan] } else { $null }
    if (-not $target) {
        return New-ApiResult -Success $false -Message "Unknown plan"
    }
    $out = powercfg /setactive $target 2>&1 | Out-String
    return New-ApiResult -Success $true -Message "Active power plan set to $Plan" -Data ([PSCustomObject]@{ Plan = $Plan; Guid = $target; Output = $out.Trim() })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
