# ResetTcpIp.ps1
try {
    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("int", "ip", "reset") -TimeoutSec 10
    return New-ApiResult -Success $true -Message "TCP/IP stack reset completed. A reboot may be required for full effect." -Data ([PSCustomObject]@{
        Output   = $r.Output
        ExitCode = $r.ExitCode
        RebootRecommended = $true
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
