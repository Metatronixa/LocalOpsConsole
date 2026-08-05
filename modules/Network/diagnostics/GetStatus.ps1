# Network adapter status (fast, resilient — avoid per-adapter NetTCPIP stalls)
try {
    $adapters = @()

    # Prefer CIM — works even when NetTCPIP module fails to load
    $cimConfigs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
        Where-Object { $_.IPEnabled -eq $true })

    foreach ($cfg in $cimConfigs) {
        $ipv4 = @($cfg.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
        $gw = @($cfg.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
        $dns = if ($cfg.DNSServerSearchOrder) { ($cfg.DNSServerSearchOrder -join ", ") } else { "-" }
        if ([string]::IsNullOrWhiteSpace($dns)) { $dns = "-" }

        $winsP = if ($cfg.WINSPrimaryServer) { [string]$cfg.WINSPrimaryServer } else { "" }
        $winsS = if ($cfg.WINSSecondaryServer) { [string]$cfg.WINSSecondaryServer } else { "" }
        $adapters += [PSCustomObject]@{
            InterfaceAlias = [string]$cfg.Description
            Status         = "Up"
            IsConnected    = $true
            IPv4Address    = if ($ipv4) { [string]$ipv4[0] } else { "-" }
            Gateway        = if ($gw) { [string]$gw[0] } else { "-" }
            DNSServers     = $dns
            LinkSpeed      = "-"
            WINSPrimary    = $winsP
            WINSSecondary  = $winsS
            NetbiosMode    = Get-LocNetbiosModeLabel -Value $cfg.TcpipNetbiosOptions
        }
    }

    # Enrich link speed/status when NetAdapter is available (best effort, never block long)
    try {
        Import-Module NetAdapter -ErrorAction SilentlyContinue | Out-Null
        $byIndex = @{}
        Get-NetAdapter -ErrorAction Stop | ForEach-Object {
            if ($null -ne $_.ifIndex) { $byIndex[[int]$_.ifIndex] = $_ }
        }
        foreach ($cfg in $cimConfigs) {
            $idx = [int]$cfg.InterfaceIndex
            if ($byIndex.ContainsKey($idx)) {
                $na = $byIndex[$idx]
                $match = $adapters | Where-Object { $_.InterfaceAlias -eq $cfg.Description } | Select-Object -First 1
                if ($match) {
                    $match.Status = [string]$na.Status
                    $match.IsConnected = ($na.Status -eq "Up")
                    $match.LinkSpeed = if ($na.LinkSpeed) { [string]$na.LinkSpeed } else { "-" }
                    if ($na.Name) { $match.InterfaceAlias = [string]$na.Name }
                }
            }
        }
    }
    catch { }

    if ($adapters.Count -eq 0) {
        return New-ApiResult -Success $true -Message "No IP-enabled adapters found" -Data @()
    }

    return New-ApiResult -Success $true -Message ("{0} network adapter(s)" -f $adapters.Count) -Data @($adapters)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
