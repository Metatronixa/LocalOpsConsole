# ResetNetsh.ps1
try {
    $r1 = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("int", "ip", "reset") -TimeoutSec 8
    $r2 = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("winsock", "reset") -TimeoutSec 8
    return New-ApiResult -Success $true -Message "Netsh IP + Winsock reset. Reboot may be required." -Data ([PSCustomObject]@{
        IpReset     = $r1.Output
        WinsockReset = $r2.Output
        RebootRecommended = $true
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
