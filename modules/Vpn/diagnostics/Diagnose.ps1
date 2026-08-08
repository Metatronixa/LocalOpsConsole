try {
    $hints = [System.Collections.Generic.List[string]]::new()
    $vpn = @(Get-VpnConnection -ErrorAction SilentlyContinue)
    $connected = @($vpn | Where-Object { $_.ConnectionStatus -eq "Connected" })
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })

    if ($vpn.Count -eq 0) { $hints.Add("No RAS VPN profiles found (third-party VPN clients may not appear here).") }
    if ($connected.Count -eq 0 -and $vpn.Count -gt 0) { $hints.Add("VPN profiles exist but none are Connected.") }
    if ($connected.Count -gt 0) { $hints.Add("Active VPN: " + (($connected | ForEach-Object Name) -join ", ")) }

    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses } |
        Select-Object -First 3
    $gw = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1

    $pingGw = $null
    if ($gw) {
        $pingGw = Test-Connection -ComputerName $gw.NextHop -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $pingGw) { $hints.Add("Default gateway $($gw.NextHop) did not respond to ping.") }
    }
    else {
        $hints.Add("No default route (0.0.0.0/0) found.")
    }

    return New-ApiResult -Success $true -Message "VPN diagnose complete" -Data ([PSCustomObject]@{
        ProfileCount     = $vpn.Count
        ConnectedCount   = $connected.Count
        UpAdapters       = $adapters.Count
        DefaultGateway   = if ($gw) { $gw.NextHop } else { $null }
        GatewayReachable = [bool]$pingGw
        DnsServers       = @($dns | ForEach-Object { $_.ServerAddresses })
        Hints            = @($hints)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
