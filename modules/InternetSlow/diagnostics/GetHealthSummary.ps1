# GetHealthSummary.ps1 — fast health snapshot (<3s)
try {
    $started = Get-Date
    $checks = @()
    $adapterBasic = Get-LocPrimaryAdapterSpeed
    $gateway = Get-LocFirstIPv4DefaultGateway

    $adapterOk = ($adapterBasic -and $adapterBasic.Status -eq 'Up')
    $checks += New-LocHealthCheck -Name "Adapter connected" -Status $(if ($adapterOk) { "OK" } else { "ERROR" }) `
        -Details $(if ($adapterBasic) { $adapterBasic.Name } else { "No active adapter" })
    if (-not $adapterOk) {
        Add-LocInternetEvent -Category "Adapter" -Severity "ERROR" -Message "No connected adapter"
    }

    $gwPing = $null
    if ($gateway) {
        $gwPing = Invoke-LocFastPing -Target $gateway -Count 1 -TimeoutMs 1200
        $gwSt = if ($gwPing.Success) { "OK" } elseif ($gwPing.LossPct -gt 0) { "WARN" } else { "ERROR" }
        $checks += New-LocHealthCheck -Name "Gateway ping ($gateway)" -Status $gwSt `
            -Details ("{0}ms / loss {1}%" -f $gwPing.AvgMs, $gwPing.LossPct)
        if ($gwSt -ne "OK") { Add-LocInternetEvent -Category "Gateway" -Severity $gwSt -Message "Gateway ping failed" -Detail $gwPing }
    }
    else {
        $checks += New-LocHealthCheck -Name "Gateway ping" -Status "WARN" -Details "No default gateway"
    }

    $dns = Invoke-LocDnsResolve -HostName "google.com" -TimeoutSec 2
    $dnsSt = if ($dns.Success) { "OK" } else { "ERROR" }
    $checks += New-LocHealthCheck -Name "DNS resolve (google.com)" -Status $dnsSt `
        -Details $(if ($dns.Success) { $dns.Address } else { $dns.Message })
    if ($dnsSt -ne "OK") { Add-LocInternetEvent -Category "DNS" -Severity "ERROR" -Message "DNS resolve failed" -Detail $dns }

    $https = Invoke-LocHttpsHead -Url "https://1.1.1.1/cdn-cgi/trace" -TimeoutSec 2
    $httpsSt = if ($https.Success) { "OK" } else { "ERROR" }
    $checks += New-LocHealthCheck -Name "HTTPS reachability" -Status $httpsSt `
        -Details ("HTTP {0} / {1}ms" -f $https.StatusCode, $https.ElapsedMs)
    if ($httpsSt -ne "OK") { Add-LocInternetEvent -Category "HTTPS" -Severity "ERROR" -Message "HTTPS check failed" -Detail $https }

    $pingCf = Invoke-LocFastPing -Target "1.1.1.1" -Count 1 -TimeoutMs 1500
    $pingSt = if ($pingCf.LossPct -le 5) { "OK" } elseif ($pingCf.LossPct -le 25) { "WARN" } else { "ERROR" }
    $checks += New-LocHealthCheck -Name "Internet latency (1.1.1.1)" -Status $pingSt `
        -Details ("avg {0}ms / loss {1}%" -f $pingCf.AvgMs, $pingCf.LossPct)
    if ($pingSt -eq "ERROR") { Add-LocInternetEvent -Category "Internet" -Severity "ERROR" -Message "High packet loss to 1.1.1.1" -Detail $pingCf }

    $okCount = @($checks | Where-Object { $_.Status -eq "OK" }).Count
    $warnCount = @($checks | Where-Object { $_.Status -eq "WARN" }).Count
    $errCount = @($checks | Where-Object { $_.Status -eq "ERROR" }).Count
    $total = $checks.Count
    $pct = if ($total -gt 0) {
        [math]::Round((($okCount * 100) + ($warnCount * 50)) / $total, 0)
    } else { 0 }

    $elapsedMs = [int][math]::Round(((Get-Date) - $started).TotalMilliseconds, 0)
    return New-ApiResult -Success $true -Message ("Health summary ({0}ms)" -f $elapsedMs) -Data ([PSCustomObject]@{
        OverallHealthPct = [int]$pct
        Checks           = @($checks)
        Adapter          = $adapterBasic
        Gateway          = $gateway
        ElapsedMs        = $elapsedMs
        Summary          = ("{0} OK, {1} WARN, {2} ERROR" -f $okCount, $warnCount, $errCount)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
