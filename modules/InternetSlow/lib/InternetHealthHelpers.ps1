# InternetHealthHelpers.ps1 — timeline, fast ping/TCP/HTTPS/DNS helpers for Internet Health module.

$script:LocInternetTimeline = [System.Collections.ArrayList]::new()
$script:LocInternetTimelineMax = 80

function Add-LocInternetEvent {
    param(
        [string]$Category = "General",
        [string]$Severity = "INFO",
        [string]$Message = "",
        [object]$Detail = $null
    )
    $evt = [PSCustomObject]@{
        At       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Category = $Category
        Severity = $Severity
        Message  = $Message
        Detail   = $Detail
    }
    [void]$script:LocInternetTimeline.Insert(0, $evt)
    while ($script:LocInternetTimeline.Count -gt $script:LocInternetTimelineMax) {
        $script:LocInternetTimeline.RemoveAt($script:LocInternetTimeline.Count - 1)
    }
    return $evt
}

function Get-LocInternetTimeline {
    return @($script:LocInternetTimeline)
}

function Invoke-LocFastPing {
    param(
        [string]$Target,
        [int]$Count = 2,
        [int]$TimeoutMs = 1500
    )
    try {
        $start = Get-Date
        $waitMs = [math]::Max(500, $TimeoutMs)
        $r = Invoke-ToolCommand -FilePath "ping.exe" -ArgumentList @("-n", [string]$Count, "-w", [string]$waitMs, $Target) -TimeoutSec ([math]::Ceiling(($waitMs * $Count + 500) / 1000.0))
        $elapsedMs = [int][math]::Round(((Get-Date) - $start).TotalMilliseconds, 0)
        $replies = @([regex]::Matches($r.Output, "(?i)Reply from|TTL=")).Count
        if ($replies -eq 0 -and $r.Output -match '(?i)time[<=](\d+)ms') {
            $replies = @([regex]::Matches($r.Output, '(?i)time[<=](\d+)ms')).Count
        }
        $successCount = $replies
        $lossPct = if ($Count -gt 0) { [math]::Round((($Count - $successCount) / $Count) * 100, 0) } else { 100 }
        $avg = 0
        if ($r.Output -match '(?i)Average\s*=\s*(\d+)ms') { $avg = [int]$Matches[1] }
        elseif ($r.Output -match '(?i)time[<=](\d+)ms') { $avg = [int]$Matches[1] }
        return [PSCustomObject]@{
            Target       = $Target
            Count        = $Count
            SuccessCount = $successCount
            LossPct      = $lossPct
            AvgMs        = $avg
            ElapsedMs    = $elapsedMs
            Success      = ($successCount -gt 0)
        }
    }
    catch {
        return [PSCustomObject]@{
            Target = $Target; Count = $Count; SuccessCount = 0; LossPct = 100; AvgMs = 0; ElapsedMs = 0; Success = $false
        }
    }
}

function Invoke-LocTcpConnect {
    param(
        [string]$HostName,
        [int]$Port = 443,
        [int]$TimeoutMs = 2000
    )
    $client = $null
    try {
        $start = Get-Date
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) {
            return [PSCustomObject]@{ Host = $HostName; Port = $Port; Success = $false; ElapsedMs = $TimeoutMs; Message = "Timeout" }
        }
        $client.EndConnect($iar)
        $ms = [int][math]::Round(((Get-Date) - $start).TotalMilliseconds, 0)
        return [PSCustomObject]@{ Host = $HostName; Port = $Port; Success = $true; ElapsedMs = $ms; Message = "Connected" }
    }
    catch {
        return [PSCustomObject]@{ Host = $HostName; Port = $Port; Success = $false; ElapsedMs = 0; Message = $_.Exception.Message }
    }
    finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}

function Invoke-LocHttpsHead {
    param(
        [string]$Url,
        [int]$TimeoutSec = 3
    )
    try {
        $start = Get-Date
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = "HEAD"
        $req.Timeout = $TimeoutSec * 1000
        $req.UserAgent = "LocalOpsConsole/InternetHealth"
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        $ms = [int][math]::Round(((Get-Date) - $start).TotalMilliseconds, 0)
        return [PSCustomObject]@{ Url = $Url; Success = ($code -ge 200 -and $code -lt 400); StatusCode = $code; ElapsedMs = $ms }
    }
    catch {
        return [PSCustomObject]@{ Url = $Url; Success = $false; StatusCode = 0; ElapsedMs = 0; Message = $_.Exception.Message }
    }
}

function Invoke-LocDnsResolve {
    param(
        [string]$HostName = "google.com",
        [int]$TimeoutSec = 2
    )
    try {
        $r = Resolve-DnsName -Name $HostName -DnsOnly -ErrorAction Stop | Select-Object -First 1
        $addr = if ($r) { [string]$r.IPAddress } else { $null }
        return [PSCustomObject]@{ HostName = $HostName; Success = [bool]$addr; Address = $addr }
    }
    catch {
        return [PSCustomObject]@{ HostName = $HostName; Success = $false; Address = $null; Message = $_.Exception.Message }
    }
}

function Get-LocActiveAdapterInfo {
    try {
        $na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false } | Select-Object -First 1
        if (-not $na) {
            $na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        }
        if (-not $na) { return $null }

        $type = if ($na.MediaType -match '802\.11|Native80211|Wireless') { 'WiFi' }
                elseif ($na.MediaType -match '802\.3|Ethernet') { 'Ethernet' }
                else { [string]$na.MediaType }

        $ipCfg = Get-NetIPConfiguration -InterfaceIndex $na.ifIndex -ErrorAction SilentlyContinue
        $ipv4 = @($ipCfg.IPv4Address | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue)
        $gw = @($ipCfg.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop -ErrorAction SilentlyContinue)
        $dns = @($ipCfg.DnsServer | Select-Object -ExpandProperty ServerAddresses -ErrorAction SilentlyContinue)
        $ipv6 = @($ipCfg.IPv6Address | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue | Select-Object -First 2)

        $mtu = $null
        try {
            $iface = Get-NetIPInterface -InterfaceIndex $na.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($iface) { $mtu = [int]$iface.NlMtu }
        }
        catch { }

        $dhcp = $false
        try {
            $dhcp = (Get-NetIPInterface -InterfaceIndex $na.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp -eq 'Enabled'
        }
        catch { }

        return [PSCustomObject]@{
            Name          = [string]$na.Name
            InterfaceIndex= [int]$na.ifIndex
            Type          = $type
            Status        = [string]$na.Status
            LinkSpeed     = [string]$na.LinkSpeed
            MacAddress    = [string]$na.MacAddress
            MediaConnected= [bool]$na.MediaConnected
            IPv4          = if ($ipv4) { [string]$ipv4[0] } else { $null }
            Gateway       = if ($gw) { [string]$gw[0] } else { $null }
            DnsServers    = ($dns -join ", ")
            DhcpEnabled   = $dhcp
            Mtu           = $mtu
            IPv6          = ($ipv6 -join ", ")
        }
    }
    catch {
        return $null
    }
}

function New-LocHealthCheck {
    param([string]$Name, [string]$Status, [string]$Details = "")
    return [PSCustomObject]@{ Name = $Name; Status = $Status; Details = $Details }
}

function Get-LocHealthStatusLabel {
    param([bool]$Ok, [bool]$Warn = $false)
    if ($Ok) { return "OK" }
    if ($Warn) { return "WARN" }
    return "ERROR"
}
