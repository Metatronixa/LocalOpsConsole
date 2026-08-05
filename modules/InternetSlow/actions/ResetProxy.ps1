# ResetProxy.ps1
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0 -ErrorAction Stop
    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("winhttp", "reset", "proxy") -TimeoutSec 5
    return New-ApiResult -Success $true -Message "Proxy settings reset (user + WinHTTP)" -Data ([PSCustomObject]@{
        WinHttpOutput = $r.Output
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
