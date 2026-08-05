try {
    $connections = @()
    $vpn = Get-VpnConnection -ErrorAction SilentlyContinue
    foreach ($v in @($vpn)) {
        $connections += [PSCustomObject]@{
            Name               = $v.Name
            ServerAddress      = $v.ServerAddress
            ConnectionStatus   = [string]$v.ConnectionStatus
            TunnelType         = [string]$v.TunnelType
            AuthenticationMethod = ($v.AuthenticationMethod -join ", ")
            Guid               = [string]$v.Guid
        }
    }

    $tunnels = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match "VPN|WAN Miniport|TAP|WireGuard|OpenVPN|Cisco|SonicWall|Fortinet|GlobalProtect" -or
        $_.Name -match "VPN|tunnel"
    } | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            Status      = [string]$_.Status
            Description = $_.InterfaceDescription
            MacAddress  = $_.MacAddress
        }
    })

    return New-ApiResult -Success $true -Message "VPN topology" -Data ([PSCustomObject]@{
        Connections = @($connections)
        Adapters    = @($tunnels)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
