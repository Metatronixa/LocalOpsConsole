# ResetWinsock.ps1
try {
    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("winsock", "reset") -TimeoutSec 10
    return New-ApiResult -Success $true -Message "Winsock reset completed. A reboot may be required for full effect." -Data ([PSCustomObject]@{
        Output   = $r.Output
        ExitCode = $r.ExitCode
        RebootRecommended = $true
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
