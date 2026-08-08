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
        if ($client) { try { $client.Close() } catch { Write-Debug $_.Exception.Message } }
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
        # Prefer timed nslookup — Resolve-DnsName has no reliable timeout and can hang the API thread.
        if (Get-Command Invoke-ToolCommand -ErrorAction SilentlyContinue) {
            $r = Invoke-ToolCommand -FilePath "nslookup.exe" -ArgumentList @($HostName) -TimeoutSec $TimeoutSec
            $addr = $null
            if ($r.Output -match '(?im)Address:\s*([0-9a-fA-F:.]+)\s*$') {
                $candidates = [regex]::Matches($r.Output, '(?im)^Address:\s*([0-9a-fA-F:.]+)\s*$')
                if ($candidates.Count -gt 0) {
                    $addr = $candidates[$candidates.Count - 1].Groups[1].Value
                    if ($addr -match '^\d+\.\d+\.\d+\.\d+$' -or $addr -match ':') { }
                    else { $addr = $null }
                }
            }
            if (-not $addr -and $r.Output -match '(?i)Name:\s*\S+\s+Address(?:es)?:\s*([0-9.]+)') {
                $addr = $Matches[1]
            }
            # Fallback parse: last IPv4 in output that isn't the DNS server line duplicated oddly
            if (-not $addr) {
                $ips = [regex]::Matches($r.Output, '\b(\d{1,3}(?:\.\d{1,3}){3})\b') | ForEach-Object { $_.Groups[1].Value }
                $addr = @($ips | Select-Object -Last 1)[0]
            }
            return [PSCustomObject]@{ HostName = $HostName; Success = [bool]$addr; Address = $addr; TimedOut = [bool]$r.TimedOut }
        }
        $job = Start-Job -ScriptBlock {
            Resolve-DnsName -Name $using:HostName -DnsOnly -ErrorAction Stop | Select-Object -First 1 -ExpandProperty IPAddress
        }
        if (-not (Wait-Job $job -Timeout $TimeoutSec)) {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ HostName = $HostName; Success = $false; Address = $null; TimedOut = $true; Message = "DNS timed out" }
        }
        $addr = Receive-Job $job
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ HostName = $HostName; Success = [bool]$addr; Address = [string]$addr; TimedOut = $false }
    }
    catch {
        return [PSCustomObject]@{ HostName = $HostName; Success = $false; Address = $null; Message = $_.Exception.Message }
    }
}

function Get-LocActiveAdapterInfo {
    try {
        # Prefer CIM — Get-NetAdapter can stall without a timeout on some hosts.
        $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -and (@($_.IPAddress) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^127\.' })
            } |
            Select-Object -First 1
        if (-not $cfg) { return $null }

        $ipv4 = @($cfg.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^127\.' } | Select-Object -First 1)
        $gw = @($cfg.DefaultIPGateway | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
        $dns = if ($cfg.DNSServerSearchOrder) { ($cfg.DNSServerSearchOrder -join ", ") } else { "" }
        $ipv6 = @($cfg.IPAddress | Where-Object { $_ -match ':' -and $_ -notmatch '(?i)^fe80:' } | Select-Object -First 1)
        if (-not $ipv6) {
            $ipv6 = @($cfg.IPAddress | Where-Object { $_ -match ':' } | Select-Object -First 1)
        }

        $name = [string]$cfg.Description
        $mac = [string]$cfg.MACAddress
        $linkSpeed = $null
        $mediaConnected = $true
        $type = "Ethernet"
        $ifIndex = [int]$cfg.InterfaceIndex
        try {
            $na = Get-CimInstance Win32_NetworkAdapter -Filter ("InterfaceIndex=$ifIndex") -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($na) {
                if ($na.NetConnectionID) { $name = [string]$na.NetConnectionID }
                if ($na.Speed -and $na.Speed -gt 0) { $linkSpeed = ("{0} Mbps" -f [math]::Round($na.Speed / 1MB, 0)) }
                if ($na.AdapterType -match '(?i)wireless|802\.11') { $type = "WiFi" }
                $mediaConnected = ($na.NetConnectionStatus -eq 2)
            }
        }
        catch { Write-Debug $_.Exception.Message }

        $mtu = $null
        $dhcp = [bool]$cfg.DHCPEnabled

        return [PSCustomObject]@{
            Name           = $name
            InterfaceIndex = $ifIndex
            Type           = $type
            Status         = if ($mediaConnected) { "Up" } else { "Disconnected" }
            LinkSpeed      = $linkSpeed
            MacAddress     = $mac
            MediaConnected = $mediaConnected
            IPv4           = if ($ipv4) { [string]$ipv4 } else { $null }
            Gateway        = if ($gw) { [string]$gw } else { $null }
            DnsServers     = $dns
            DhcpEnabled    = $dhcp
            Mtu            = $mtu
            IPv6           = if ($ipv6) { [string]$ipv6 } else { $null }
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
