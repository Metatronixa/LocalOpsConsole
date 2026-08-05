# GetVpnHealth.ps1 — never expose passwords
try {
    $connections = @()
    $vpn = Get-VpnConnection -ErrorAction SilentlyContinue
    foreach ($v in @($vpn)) {
        $connections += [PSCustomObject]@{
            Name             = [string]$v.Name
            ServerAddress    = [string]$v.ServerAddress
            ConnectionStatus = [string]$v.ConnectionStatus
            TunnelType       = [string]$v.TunnelType
            SplitTunneling   = [bool]$v.SplitTunneling
        }
    }

    $connected = @($connections | Where-Object { $_.ConnectionStatus -eq 'Connected' })
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match "VPN|WAN Miniport|TAP|WireGuard|OpenVPN" -or $_.Name -match "VPN|tunnel"
    } | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            Status      = [string]$_.Status
            Description = $_.InterfaceDescription
        }
    })

    return New-ApiResult -Success $true -Message ("{0} VPN profile(s), {1} connected" -f $connections.Count, $connected.Count) -Data ([PSCustomObject]@{
        Connections       = @($connections)
        ConnectedCount    = $connected.Count
        TunnelAdapters    = @($adapters)
        AnyConnected      = ($connected.Count -gt 0)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
