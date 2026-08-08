# RunConnectivityTest.ps1 — single connectivity test (<3s)
param(
    [ValidateSet("GatewayPing", "GoogleDns", "CloudflareDns", "Microsoft", "GitHub", "DnsResolve", "Https", "Tcp443", "Tcp80", "ProxyDetect", "Ntp")]
    [string]$Test = "GatewayPing"
)

try {
    $result = $null
    switch ($Test) {
        "GatewayPing" {
            $gw = Get-LocFirstIPv4DefaultGateway
            if (-not $gw) {
                return New-ApiResult -Success $false -Message "No default gateway" -Data ([PSCustomObject]@{ Test = $Test })
            }
            $result = Invoke-LocFastPing -Target $gw -Count 2 -TimeoutMs 1200
        }
        "GoogleDns" { $result = Invoke-LocFastPing -Target "8.8.8.8" -Count 2 -TimeoutMs 1200 }
        "CloudflareDns" { $result = Invoke-LocFastPing -Target "1.1.1.1" -Count 2 -TimeoutMs 1200 }
        "Microsoft" { $result = Invoke-LocHttpsHead -Url "https://www.microsoft.com" -TimeoutSec 3 }
        "GitHub" { $result = Invoke-LocHttpsHead -Url "https://github.com" -TimeoutSec 3 }
        "DnsResolve" { $result = Invoke-LocDnsResolve -HostName "google.com" -TimeoutSec 2 }
        "Https" { $result = Invoke-LocHttpsHead -Url "https://httpbin.org/get" -TimeoutSec 3 }
        "Tcp443" { $result = Invoke-LocTcpConnect -HostName "1.1.1.1" -Port 443 -TimeoutMs 2000 }
        "Tcp80" { $result = Invoke-LocTcpConnect -HostName "1.1.1.1" -Port 80 -TimeoutMs 2000 }
        "ProxyDetect" {
            $proxy = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
            $winhttp = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("winhttp", "show", "proxy") -TimeoutSec 3
            $result = [PSCustomObject]@{
                ProxyEnable = [bool]$proxy.ProxyEnable
                ProxyServer = [string]$proxy.ProxyServer
                WinHttp     = ($winhttp.Output -split "`n" | Select-Object -First 5) -join "`n"
            }
        }
        "Ntp" { $result = Invoke-LocTcpConnect -HostName "time.windows.com" -Port 123 -TimeoutMs 2000 }
    }

    $ok = $true
    if ($result -and ($result.PSObject.Properties.Name -contains 'Success')) {
        $ok = [bool]$result.Success
    }
    elseif ($result -and ($result.PSObject.Properties.Name -contains 'LossPct')) {
        $ok = ($result.LossPct -le 25)
    }

    if (-not $ok) {
        Add-LocInternetEvent -Category "ConnectivityTest" -Severity "WARN" -Message "Test $Test failed" -Detail $result
    }

    $passLabel = if ($ok) { 'pass' } else { 'fail' }
    return New-ApiResult -Success $true -Message ("Test: {0} - {1}" -f $Test, $passLabel) -Data ([PSCustomObject]@{
        Test    = $Test
        Passed  = $ok
        Result  = $result
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -Data ([PSCustomObject]@{ Test = $Test })
}
