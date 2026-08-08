# Printers helpers — shared port/host resolution, network probes, spooler info

function Get-LocDefaultPrinterName {
    try {
        $def = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Default } | Select-Object -First 1
        if ($def) { return [string]$def.Name }
        $wmi = Get-CimInstance -ClassName Win32_Printer -Filter "Default='True'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wmi) { return [string]$wmi.Name }
    }
    catch { Write-Debug $_.Exception.Message }
    return ""
}

function Get-LocPrinterPortInfo {
    param([string]$PortName)
    if ([string]::IsNullOrWhiteSpace($PortName)) { return $null }

    $port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $port) { return $null }

    $hostAddr = ""
    foreach ($prop in @("PrinterHostAddress", "HostAddress")) {
        if ($port.PSObject.Properties.Name -contains $prop -and $port.$prop) {
            $hostAddr = [string]$port.$prop
            break
        }
    }

    return [PSCustomObject]@{
        PortName         = [string]$port.Name
        Description      = if ($port.Description) { [string]$port.Description } else { "" }
        HostAddress      = $hostAddr
        PortNumber       = if ($null -ne $port.PortNumber) { [int]$port.PortNumber } else { 0 }
        Protocol         = if ($port.Protocol) { [string]$port.Protocol } else { "" }
        SNMPEnabled      = if ($null -ne $port.SNMP) { [bool]$port.SNMP } elseif ($port.PSObject.Properties.Name -contains "SNMPEnabled") { [bool]$port.SNMPEnabled } else { $false }
        PortMonitor      = if ($port.PortMonitor) { [string]$port.PortMonitor } else { "" }
        Type             = Get-LocPortType -PortName $PortName -PortObject $port
    }
}

function Get-LocPortType {
    param(
        [string]$PortName,
        [object]$PortObject = $null
    )
    $name = [string]$PortName
    if ($name -match '^WSD-|^WSD$') { return "WSD" }
    if ($name -match '^USB') { return "USB" }
    if ($name -match '^LPT\d') { return "LPT" }
    if ($name -match '^COM\d') { return "COM" }
    if ($name -match '^IP_|^TCP|^192\.|^10\.|^172\.' ) { return "TCP/IP" }

    if ($PortObject) {
        $hostAddr = ""
        foreach ($prop in @("PrinterHostAddress", "HostAddress")) {
            if ($PortObject.PSObject.Properties.Name -contains $prop -and $PortObject.$prop) {
                $hostAddr = [string]$PortObject.$prop
                break
            }
        }
        if ($hostAddr) { return "TCP/IP" }
        $desc = [string]$PortObject.Description
        if ($desc -match 'WSD') { return "WSD" }
        if ($desc -match 'USB') { return "USB" }
        if ($desc -match 'Standard TCP') { return "TCP/IP" }
    }
    return "Other"
}

function Resolve-LocPrinterNetworkTarget {
    param(
        [string]$TargetHost,
        [string]$PrinterName
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetHost)) {
        return [PSCustomObject]@{ Host = $TargetHost.Trim(); PrinterName = $PrinterName; PortName = "" }
    }
    if ([string]::IsNullOrWhiteSpace($PrinterName)) {
        return $null
    }
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $printer) { return $null }
    $portInfo = Get-LocPrinterPortInfo -PortName $printer.PortName
    $hostAddr = if ($portInfo) { $portInfo.HostAddress } else { "" }
    if ([string]::IsNullOrWhiteSpace($hostAddr)) {
        if ($printer.PortName -match '(\d{1,3}(?:\.\d{1,3}){3})') {
            $hostAddr = $Matches[1]
        }
    }
    return [PSCustomObject]@{
        Host        = $hostAddr
        PrinterName = $PrinterName
        PortName    = [string]$printer.PortName
    }
}

function Format-LocJobAge {
    param([datetime]$SubmittedTime)
    if (-not $SubmittedTime -or $SubmittedTime -eq [datetime]::MinValue) { return "" }
    $span = (Get-Date) - $SubmittedTime
    if ($span.TotalDays -ge 1) { return ("{0:N1}d" -f $span.TotalDays) }
    if ($span.TotalHours -ge 1) { return ("{0:N0}h" -f $span.TotalHours) }
    if ($span.TotalMinutes -ge 1) { return ("{0:N0}m" -f $span.TotalMinutes) }
    return ("{0:N0}s" -f [math]::Max(0, $span.TotalSeconds))
}

function Get-LocSpoolerRecoveryInfo {
    $recovery = [PSCustomObject]@{
        ResetPeriod = ""
        RebootMsg   = ""
        Actions     = @()
    }
    try {
        $raw = & sc.exe qfailure Spooler 2>&1 | Out-String
        if ($raw) {
            $lines = @($raw -split "`r?`n" | Where-Object { $_.Trim() })
            foreach ($line in $lines) {
                if ($line -match 'RESET_PERIOD\s*:\s*(.+)') { $recovery.ResetPeriod = $Matches[1].Trim() }
                if ($line -match 'REBOOT MESSAGE\s*:\s*(.+)') { $recovery.RebootMsg = $Matches[1].Trim() }
                if ($line -match '^\s*(\d+)\s*:\s*(.+)') {
                    $recovery.Actions += [PSCustomObject]@{ Index = [int]$Matches[1]; Action = $Matches[2].Trim() }
                }
            }
        }
    }
    catch { Write-Debug $_.Exception.Message }
    return $recovery
}

function Test-LocTcpPortOpen {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = 2000
    )
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return [PSCustomObject]@{ Open = $false; LatencyMs = $null; Error = "No host" }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) {
            $client.Close()
            return [PSCustomObject]@{ Open = $false; LatencyMs = $null; Error = "Timeout" }
        }
        $client.EndConnect($iar)
        $sw.Stop()
        $client.Close()
        return [PSCustomObject]@{ Open = $true; LatencyMs = [int]$sw.ElapsedMilliseconds; Error = "" }
    }
    catch {
        $sw.Stop()
        return [PSCustomObject]@{ Open = $false; LatencyMs = $null; Error = $_.Exception.Message }
    }
}

function Invoke-LocPrinterNetworkProbe {
    param(
        [string]$HostName,
        [int]$MaxTotalMs = 8000
    )
    $deadline = [datetime]::UtcNow.AddMilliseconds($MaxTotalMs)
    $remaining = { param([int]$budget) $null = $budget; [math]::Max(500, [int](($deadline - [datetime]::UtcNow).TotalMilliseconds)) }

    $result = [ordered]@{
        Host          = $HostName
        Ping          = $null
        Dns           = $null
        Tcp9100       = $null
        Tcp515        = $null
        Http          = $null
        Https         = $null
        Ipv6          = $null
        PacketLossPct = $null
        AvgLatencyMs  = $null
    }

    # Ping (2 probes, short timeout)
    try {
        $null = & $remaining 2500
        $pings = @(Test-Connection -ComputerName $HostName -Count 2 -ErrorAction SilentlyContinue)
        $ok = @($pings | Where-Object { $_.StatusCode -eq 0 -or $_.ResponseTime -ge 0 })
        $loss = if ($pings.Count -gt 0) { [math]::Round((($pings.Count - $ok.Count) / $pings.Count) * 100, 0) } else { 100 }
        $avg = if ($ok.Count) { [math]::Round(($ok | Measure-Object ResponseTime -Average).Average, 1) } else { $null }
        $result.Ping = [PSCustomObject]@{
            Success       = ($ok.Count -gt 0)
            Replies       = $ok.Count
            Sent          = $pings.Count
            AvgLatencyMs  = $avg
            PacketLossPct = $loss
        }
        $result.PacketLossPct = $loss
        $result.AvgLatencyMs = $avg
    }
    catch {
        $result.Ping = [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
    }

    # DNS A + AAAA
    try {
        $dnsA = Resolve-DnsName -Name $HostName -Type A -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'A' }
        $dnsAAAA = Resolve-DnsName -Name $HostName -Type AAAA -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'AAAA' }
        $result.Dns = [PSCustomObject]@{
            Success = ($dnsA -or $dnsAAAA)
            A       = @($dnsA | ForEach-Object { $_.IPAddress })
            AAAA    = @($dnsAAAA | ForEach-Object { $_.IPAddress })
        }
    }
    catch {
        $result.Dns = [PSCustomObject]@{ Success = $false; Error = $_.Exception.Message }
    }

    if ([datetime]::UtcNow -ge $deadline) { return [PSCustomObject]$result }

    $tcpBudget = & $remaining 1500
    $result.Tcp9100 = Test-LocTcpPortOpen -HostName $HostName -Port 9100 -TimeoutMs $tcpBudget
    if ([datetime]::UtcNow -lt $deadline) {
        $result.Tcp515 = Test-LocTcpPortOpen -HostName $HostName -Port 515 -TimeoutMs (& $remaining 1500)
    }

    # HTTP/HTTPS best-effort
    foreach ($scheme in @("http", "https")) {
        if ([datetime]::UtcNow -ge $deadline) { break }
        $sec = [math]::Max(1, [int]((& $remaining 1200) / 1000))
        try {
            $uri = "${scheme}://$HostName/"
            $resp = Invoke-WebRequest -Uri $uri -Method Head -TimeoutSec $sec -UseBasicParsing -ErrorAction Stop
            $probe = [PSCustomObject]@{ Success = $true; StatusCode = [int]$resp.StatusCode }
        }
        catch {
            $code = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $code = [int]$_.Exception.Response.StatusCode
            }
            $probe = [PSCustomObject]@{
                Success    = ($null -ne $code)
                StatusCode = $code
                Error      = if ($code) { "" } else { $_.Exception.Message }
            }
        }
        if ($scheme -eq "http") { $result.Http = $probe } else { $result.Https = $probe }
    }

    # IPv6 reachability if AAAA exists
    if ($result.Dns -and $result.Dns.AAAA -and $result.Dns.AAAA.Count -gt 0 -and [datetime]::UtcNow -lt $deadline) {
        $v6 = $result.Dns.AAAA[0]
        try {
            $p6 = @(Test-Connection -ComputerName $v6 -Count 1 -ErrorAction SilentlyContinue)
            $ok6 = @($p6 | Where-Object { $_.StatusCode -eq 0 -or $_.ResponseTime -ge 0 })
            $result.Ipv6 = [PSCustomObject]@{
                Address      = $v6
                Success      = ($ok6.Count -gt 0)
                AvgLatencyMs = if ($ok6.Count) { $ok6[0].ResponseTime } else { $null }
            }
        }
        catch {
            $result.Ipv6 = [PSCustomObject]@{ Address = $v6; Success = $false; Error = $_.Exception.Message }
        }
    }

    return [PSCustomObject]$result
}

function Get-LocPrinterDriverInfo {
    param([string]$DriverName)
    $info = [PSCustomObject]@{
        Name    = $DriverName
        Version = ""
        Date    = ""
    }
    if ([string]::IsNullOrWhiteSpace($DriverName)) { return $info }

    try {
        $drv = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($drv) {
            if ($drv.DriverVersion) { $info.Version = [string]$drv.DriverVersion }
            if ($drv.MajorVersion -or $drv.MinorVersion) {
                $info.Version = ("{0}.{1}" -f $drv.MajorVersion, $drv.MinorVersion)
            }
            if ($drv.DriverDate) {
                $info.Date = $drv.DriverDate.ToString("yyyy-MM-dd")
            }
        }
    }
    catch { Write-Debug $_.Exception.Message }

    if (-not $info.Version) {
        try {
            $wmi = Get-CimInstance -ClassName Win32_PrinterDriver -Filter "Name='$($DriverName.Replace("'","''"))'" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($wmi) {
                if ($wmi.Version) { $info.Version = [string]$wmi.Version }
                if ($wmi.DriverDate) {
                    $dt = [Management.ManagementDateTimeConverter]::ToDateTime($wmi.DriverDate)
                    $info.Date = $dt.ToString("yyyy-MM-dd")
                }
            }
        }
        catch { Write-Debug $_.Exception.Message }
    }

    return $info
}

function Get-LocPrinterLastError {
    param([string]$PrinterName)
    try {
        $ev = Get-WinEvent -FilterHashtable @{
            LogName   = "Microsoft-Windows-PrintService/Operational"
            Level     = 1, 2, 3
            StartTime = (Get-Date).AddDays(-7)
        } -MaxEvents 30 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -and $_.Message -like "*$PrinterName*" } |
            Select-Object -First 1
        if ($ev) {
            $msg = $ev.Message
            if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
            return [PSCustomObject]@{
                TimeCreated = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                Id          = $ev.Id
                Message     = $msg
            }
        }
    }
    catch { Write-Debug $_.Exception.Message }
    return $null
}
