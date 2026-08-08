# AgentTelemetry.ps1 - Heartbeat telemetry collection

function Get-AgentDiskIoMBps {
    $read = $null
    $write = $null
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        if ($perf) {
            $read = [math]::Round(([double]$perf.DiskReadBytesPerSec) / 1MB, 2)
            $write = [math]::Round(([double]$perf.DiskWriteBytesPerSec) / 1MB, 2)
        }
    }
    catch { }
    return @{ Read = $read; Write = $write }
}

function Get-AgentTelemetry {
    $cpu = $null
    try {
        $c = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c -and $c.LoadPercentage -ne $null) { $cpu = [double]$c.LoadPercentage }
    }
    catch { }

    $ramPct = $null
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $total = [double]$os.TotalVisibleMemorySize
            $free = [double]$os.FreePhysicalMemory
            if ($total -gt 0) { $ramPct = [math]::Round((($total - $free) / $total) * 100, 1) }
        }
    }
    catch { }

    $diskFreePct = $null
    try {
        $sys = $env:SystemDrive
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sys'" -ErrorAction SilentlyContinue
        if ($d -and $d.Size -gt 0) {
            $diskFreePct = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
        }
    }
    catch { }

    $io = Get-AgentDiskIoMBps

    $ipv4 = $null
    $gateway = $null
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
            Select-Object -First 1
        if ($cfg) {
            $ipv4 = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
            $gateway = $cfg.IPv4DefaultGateway.NextHop
        }
    }
    catch { }

    $winVer = $null
    $uptimeSec = $null
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $winVer = "$($os.Caption) $($os.Version)"
            $uptimeSec = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds
        }
    }
    catch { }

    $internetOk = $null
    try {
        $job = Start-Job -ScriptBlock {
            Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
        }
        if (Wait-Job $job -Timeout 3) {
            $internetOk = [bool](Receive-Job $job)
        }
        else {
            Stop-Job $job -ErrorAction SilentlyContinue
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    catch { }

    $caps = @()
    try { $caps = @(Get-LocAgentCapabilities) } catch { $caps = @() }

    return @{
        ComputerName   = $env:COMPUTERNAME
        UserName       = "$env:USERDOMAIN\$env:USERNAME"
        CpuPct         = $cpu
        RamPct         = $ramPct
        DiskFreePct    = $diskFreePct
        DiskReadMBps   = $io.Read
        DiskWriteMBps  = $io.Write
        IPv4           = $ipv4
        Gateway        = $gateway
        WindowsVersion = $winVer
        UptimeSec      = $uptimeSec
        InternetOk     = $internetOk
        AgentVersion   = $AgentVersion
        Capabilities   = @($caps)
    }
}

function Send-AgentHeartbeat {
    try {
        $tel = Get-AgentTelemetry
        $resp = Invoke-AgentApi -Method POST -Path "/api/v1/fleet/heartbeat" -Body $tel -Signed -TimeoutSec 20
        if (-not $resp.Success) {
            Write-AgentLog "Heartbeat rejected: $($resp.Message)" "WARN"
        }
    }
    catch {
        Write-AgentLog "Heartbeat error: $($_.Exception.Message)" "WARN"
    }
}
