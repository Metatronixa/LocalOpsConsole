# InternetIsSlow.ps1
# Engine: consolidated “Internet is Slow” troubleshooting report (Tier 3).

try {
    $started = Get-Date

    $dnsHost = "google.com"
    $gateway = Get-LocFirstIPv4DefaultGateway
    $ifaceInfo = Get-LocPrimaryIPv4InterfaceInfo
    $adapter = Get-LocPrimaryAdapterSpeed

    # Keep ping counts small for responsiveness.
    $pingCount = 4

    $dns = Invoke-LocDnsLookup -HostName $dnsHost -TimeoutSec 6
    $ping8 = Invoke-LocPingStats -Target "8.8.8.8" -Count $pingCount

    $pingGw = $null
    if ($gateway) {
        $pingGw = Invoke-LocPingStats -Target $gateway -Count $pingCount
    }

    $tcpGlobals = Invoke-LocTcpGlobals -TimeoutSec 6
    $fw = Invoke-LocFirewallProfileSummary

    # Heuristics (fast + safe, prototype quality)
    $checks = @()

    $dnsStatus = if ($dns.Success) { "Status: OK" } else { "Status: WARN" }
    $checks += [PSCustomObject]@{ Name = "DNS lookup ($dnsHost)"; Status = $dnsStatus; Details = if ($dns.Success) { "Resolved successfully. " } else { "Lookup failed. Check DNS client settings / resolver availability." } }

    $ping8Status = if ($ping8.LossPct -le 5) { "Status: OK" } elseif ($ping8.LossPct -le 20) { "Status: WARN" } else { "Status: ERROR" }
    $checks += [PSCustomObject]@{ Name = "Reachability (8.8.8.8)"; Status = $ping8Status; Details = ("Loss {0}% / Avg {1}ms" -f $ping8.LossPct, $ping8.AvgMs) }

    if ($gateway) {
        $gwStatus = if ($pingGw.LossPct -le 5) { "Status: OK" } elseif ($pingGw.LossPct -le 20) { "Status: WARN" } else { "Status: ERROR" }
        $checks += [PSCustomObject]@{ Name = "Gateway reachability ($gateway)"; Status = $gwStatus; Details = ("Loss {0}% / Avg {1}ms" -f $pingGw.LossPct, $pingGw.AvgMs) }
    }
    else {
        $checks += [PSCustomObject]@{ Name = "Gateway reachability"; Status = "Status: WARN"; Details = "Default gateway not detected from local routing/config." }
    }

    if ($ifaceInfo -and $ifaceInfo.NlMtu) {
        $mtu = [int]$ifaceInfo.NlMtu
        $mtuStatus = if ($mtu -ge 1480) { "Status: OK" } elseif ($mtu -ge 1400) { "Status: WARN" } else { "Status: ERROR" }
        $checks += [PSCustomObject]@{ Name = "Interface MTU (best-effort)"; Status = $mtuStatus; Details = ("MTU {0} (InterfaceMetric {1})" -f $mtu, $ifaceInfo.InterfaceMetric) }
    }
    else {
        $checks += [PSCustomObject]@{ Name = "Interface MTU (best-effort)"; Status = "Status: WARN"; Details = "MTU could not be determined quickly (falling back to ping/DNS evidence)." }
    }

    if ($adapter -and $adapter.LinkSpeed) {
        $checks += [PSCustomObject]@{ Name = "Adapter link speed (best-effort)"; Status = "Status: OK"; Details = ("{0} / {1}" -f $adapter.Name, $adapter.LinkSpeed) }
    }

    if ($tcpGlobals.Success) {
        $checks += [PSCustomObject]@{ Name = "TCP global settings (netsh)"; Status = "Status: OK"; Details = "Queried successfully." }
    }
    else {
        $checks += [PSCustomObject]@{ Name = "TCP global settings (netsh)"; Status = "Status: WARN"; Details = "netsh interface tcp show global failed (best-effort)." }
    }

    # Probable cause
    $probableCause = $null
    if ($dns.Success -eq $false -and $ping8.LossPct -le 5) {
        $probableCause = "Likely DNS resolution issue: name lookup fails while raw IP connectivity looks healthy."
    }
    elseif ($ping8.LossPct -gt 20) {
        $probableCause = "Likely upstream packet loss: connectivity to 8.8.8.8 is unstable."
    }
    elseif ($gateway -and $pingGw.LossPct -gt 20) {
        $probableCause = "Likely local link or switching issue: high packet loss to the default gateway."
    }
    elseif ($ifaceInfo -and $ifaceInfo.NlMtu -and ([int]$ifaceInfo.NlMtu) -lt 1480) {
        $probableCause = "Possible MTU/encapsulation problem: interface MTU is lower than expected, which can cause slow/fragmented flows."
    }
    else {
        $probableCause = "Likely route/ISP path issue (or Wi-Fi interference). Prototype heuristics cannot pinpoint beyond local evidence."
    }

    # Recommended actions
    $actions = @()
    $actions += [PSCustomObject]@{ Step = 1; Action = "Verify physical layer: reseat cable / try a different port / test with Wi-Fi disabled (if applicable)." }

    if ($dns.Success -eq $false) {
        $actions += [PSCustomObject]@{ Step = 2; Action = "Fix DNS: set known-good DNS servers or reset network adapter DNS configuration; then re-run this engine." }
    }
    if ($gateway -and $pingGw.LossPct -gt 20) {
        $actions += [PSCustomObject]@{ Step = 3; Action = ("Investigate switch/Wi-Fi path to gateway ({0}). Try another cable/port or move closer to AP." -f $gateway) }
    }
    if ($ping8.LossPct -gt 20 -or ($gateway -and $pingGw.LossPct -gt 20)) {
        $actions += [PSCustomObject]@{ Step = ($actions.Count + 1); Action = "If packet loss persists, verify ISP connection and router health; then test again from another device." }
    }
    if ($ifaceInfo -and $ifaceInfo.NlMtu -and ([int]$ifaceInfo.NlMtu) -lt 1400) {
        $actions += [PSCustomObject]@{ Step = ($actions.Count + 1); Action = "Investigate MTU: check PPPoE/VPN/adapter settings; ensure consistent MTU end-to-end." }
    }

    # Report
    $elapsedSec = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $gatewayStr = if (-not [string]::IsNullOrWhiteSpace($gateway)) { $gateway } else { 'N/A' }
    $dnsStr = if ($dns.Success) { 'OK' } else { 'FAIL' }
    $report = [PSCustomObject]@{
        Engine            = "InternetIsSlow"
        Summary           = ("Completed in {0}s. Gateway={1}. DNS={2}." -f $elapsedSec, $gatewayStr, $dnsStr)
        Checks            = @($checks)
        ProbableCause     = $probableCause
        RecommendedActions= @($actions)
        Evidence          = [PSCustomObject]@{
            Gateway                 = $gateway
            Interface               = $ifaceInfo
            Adapter                 = $adapter
            Dns                     = $dns
            Ping8Google             = $ping8
            PingGateway             = $pingGw
            TcpGlobals              = $tcpGlobals
            FirewallProfiles        = $fw
        }
    }

    return New-ApiResult -Success $true -Message "Internet is Slow report" -Data $report
}
catch {
    return New-ApiResult -Success $false -Message "InternetIsSlow engine failed: $($_.Exception.Message)" -Data @{}
}

