# ClearArp.ps1
try {
    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("interface", "ip", "delete", "arpcache") -TimeoutSec 5
    return New-ApiResult -Success $true -Message "ARP cache cleared" -Data ([PSCustomObject]@{
        Output   = $r.Output
        ExitCode = $r.ExitCode
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
