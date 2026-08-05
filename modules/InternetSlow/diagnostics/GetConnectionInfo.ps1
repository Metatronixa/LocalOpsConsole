# GetConnectionInfo.ps1 — active adapter details
try {
    $info = Get-LocActiveAdapterInfo
    if (-not $info) {
        return New-ApiResult -Success $true -Message "No active adapter" -Data ([PSCustomObject]@{ Connected = $false })
    }

    $lease = $null
    try {
        $leaseObj = Get-NetIPAddress -InterfaceIndex $info.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($leaseObj) {
            $lease = [PSCustomObject]@{
                PrefixLength = $leaseObj.PrefixLength
                ValidLifetime = if ($leaseObj.ValidLifetime) { [string]$leaseObj.ValidLifetime } else { $null }
            }
        }
    }
    catch { }

    return New-ApiResult -Success $true -Message "Connection info" -Data ([PSCustomObject]@{
        Connected    = $true
        Name         = $info.Name
        Type         = $info.Type
        LinkSpeed    = $info.LinkSpeed
        MacAddress   = $info.MacAddress
        IPv4         = $info.IPv4
        Gateway      = $info.Gateway
        DnsServers   = $info.DnsServers
        DhcpEnabled  = $info.DhcpEnabled
        Lease        = $lease
        Mtu          = $info.Mtu
        IPv6         = $info.IPv6
        Status       = $info.Status
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
