# GetProxyInfo.ps1
try {
    $ie = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    $winhttp = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("winhttp", "show", "proxy") -TimeoutSec 3

    return New-ApiResult -Success $true -Message "Proxy settings" -Data ([PSCustomObject]@{
        ProxyEnable       = [bool]$ie.ProxyEnable
        ProxyServer       = [string]$ie.ProxyServer
        AutoConfigURL     = [string]$ie.AutoConfigURL
        ProxyOverride     = [string]$ie.ProxyOverride
        WinHttpProxy      = ($winhttp.Output -split "`r?`n" | Select-Object -First 8) -join "`n"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
