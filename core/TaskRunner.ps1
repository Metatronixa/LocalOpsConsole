# core/TaskRunner.ps1 - Lightweight telemetry (must never block the HTTP loop)

$script:LocTaskRunnerEnabled = $false
$script:LocTelemetryLastUpdate = $null
$script:LocNetPrev = $null
$script:LocDiskIoPrev = $null
$script:LocTelemetry = @{
    Cpu     = $null
    Memory  = $null
    Disk    = $null
    Disks   = $null
    DiskIo  = $null
    Network = $null
    Gpu     = $null
    Battery = $null
    Devices = $null
    Host    = $null
    Updated = $null
}

function Get-LocTelemetry {
    return [PSCustomObject]@{
        Cpu     = $script:LocTelemetry.Cpu
        Memory  = $script:LocTelemetry.Memory
        Disk    = $script:LocTelemetry.Disk
        Disks   = $script:LocTelemetry.Disks
        DiskIo  = $script:LocTelemetry.DiskIo
        Network = $script:LocTelemetry.Network
        Gpu     = $script:LocTelemetry.Gpu
        Battery = $script:LocTelemetry.Battery
        Devices = $script:LocTelemetry.Devices
        Host    = $script:LocTelemetry.Host
        Updated = $script:LocTelemetry.Updated
    }
}

function Test-LocPendingReboot {
    try {
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        )
        foreach ($k in $rebootKeys) {
            if (Test-Path $k) { return $true }
        }
        $val = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($val -and $val.PendingFileRenameOperations) { return $true }
    }
    catch { }
    return $false
}

function Get-LocNetworkByteCounters {
    # Sum active non-loopback interfaces
    try {
        $rows = @(Get-CimInstance -ClassName Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction Stop |
            Where-Object {
                $_.Name -and
                $_.Name -notmatch '(?i)isatap|teredo|loopback|Pseudo' -and
                ($_.BytesSentPersec -gt 0 -or $_.BytesReceivedPersec -gt 0 -or $_.BytesTotalPersec -gt 0)
            })
        if (-not $rows.Count) {
            $rows = @(Get-CimInstance -ClassName Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction Stop |
                Where-Object { $_.Name -and $_.Name -notmatch '(?i)isatap|teredo|loopback|Pseudo' })
        }
        $sent = [int64]0
        $recv = [int64]0
        foreach ($r in $rows) {
            # Raw counters: BytesSentPersec / BytesReceivedPersec are cumulative counters despite the name
            $sent += [int64]$r.BytesSentPersec
            $recv += [int64]$r.BytesReceivedPersec
        }
        return [PSCustomObject]@{ Sent = $sent; Recv = $recv; At = (Get-Date) }
    }
    catch {
        return $null
    }
}

function Get-LocDiskIoCounters {
    # Physical disk _Total — DiskReadBytesPersec etc. are cumulative despite the name
    try {
        $row = Get-CimInstance -ClassName Win32_PerfRawData_PerfDisk_PhysicalDisk -ErrorAction Stop |
            Where-Object { $_.Name -eq '_Total' } |
            Select-Object -First 1
        if (-not $row) { return $null }
        return [PSCustomObject]@{
            ReadBytes  = [int64]$row.DiskReadBytesPersec
            WriteBytes = [int64]$row.DiskWriteBytesPersec
            Reads      = [int64]$row.DiskReadsPersec
            Writes     = [int64]$row.DiskWritesPersec
            At         = (Get-Date)
        }
    }
    catch {
        return $null
    }
}

function Update-LocTelemetry {
    # Fast CIM only - never Invoke-LocModuleAction / GetStatus here
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -Property LoadPercentage, Name, NumberOfCores, NumberOfLogicalProcessors -ErrorAction Stop |
            Select-Object -First 1
        $usage = 0
        if ($null -ne $cpu.LoadPercentage) { $usage = [int]$cpu.LoadPercentage }

        $script:LocTelemetry.Cpu = [PSCustomObject]@{
            Name     = [string]$cpu.Name
            Cores    = [int]$cpu.NumberOfCores
            Logical  = [int]$cpu.NumberOfLogicalProcessors
            UsagePct = $usage
        }

        $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize, LastBootUpTime, CSName -ErrorAction Stop
        $totalMb = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
        $freeMb = [math]::Round($os.FreePhysicalMemory / 1024, 0)
        $usedMb = [math]::Max(0, $totalMb - $freeMb)
        $usedPct = if ($totalMb -gt 0) { [math]::Round(($usedMb / $totalMb) * 100, 0) } else { 0 }

        $script:LocTelemetry.Memory = [PSCustomObject]@{
            TotalMB = $totalMb
            UsedMB  = $usedMb
            FreeMB  = $freeMb
            UsedPct = $usedPct
            TotalGB = [math]::Round($totalMb / 1024, 1)
            UsedGB  = [math]::Round($usedMb / 1024, 1)
        }

        # All fixed disks + primary Disk for header
        try {
            $diskRows = @()
            Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -Property Size, FreeSpace, DeviceID, VolumeName, DriveType -ErrorAction Stop |
                ForEach-Object {
                    if ($_.Size -and $_.Size -gt 0) {
                        $sizeGb = [math]::Round($_.Size / 1GB, 1)
                        $freeGb = [math]::Round($_.FreeSpace / 1GB, 1)
                        $usedDiskPct = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 0)
                        $diskRows += [PSCustomObject]@{
                            Letter     = [string]$_.DeviceID
                            VolumeName = [string]$_.VolumeName
                            SizeGB     = $sizeGb
                            FreeGB     = $freeGb
                            UsedPct    = $usedDiskPct
                        }
                    }
                }
            $script:LocTelemetry.Disks = @($diskRows)
            $primary = $diskRows | Where-Object { $_.Letter -eq 'C:' } | Select-Object -First 1
            if (-not $primary) { $primary = $diskRows | Select-Object -First 1 }
            $script:LocTelemetry.Disk = $primary
        }
        catch {
            $script:LocTelemetry.Disk = $null
            $script:LocTelemetry.Disks = @()
        }

        # Disk I/O rates (MB/s + IOPS) from physical disk _Total
        $readMBps = 0.0
        $writeMBps = 0.0
        $readIops = 0.0
        $writeIops = 0.0
        try {
            $dio = Get-LocDiskIoCounters
            if ($dio -and $script:LocDiskIoPrev) {
                $dt = ($dio.At - $script:LocDiskIoPrev.At).TotalSeconds
                if ($dt -gt 0.2) {
                    $dRead = [double]($dio.ReadBytes - $script:LocDiskIoPrev.ReadBytes)
                    $dWrite = [double]($dio.WriteBytes - $script:LocDiskIoPrev.WriteBytes)
                    $dReads = [double]($dio.Reads - $script:LocDiskIoPrev.Reads)
                    $dWrites = [double]($dio.Writes - $script:LocDiskIoPrev.Writes)
                    if ($dRead -lt 0) { $dRead = 0 }
                    if ($dWrite -lt 0) { $dWrite = 0 }
                    if ($dReads -lt 0) { $dReads = 0 }
                    if ($dWrites -lt 0) { $dWrites = 0 }
                    $readMBps = [math]::Round($dRead / $dt / 1MB, 2)
                    $writeMBps = [math]::Round($dWrite / $dt / 1MB, 2)
                    $readIops = [math]::Round($dReads / $dt, 1)
                    $writeIops = [math]::Round($dWrites / $dt, 1)
                }
            }
            if ($dio) { $script:LocDiskIoPrev = $dio }
        }
        catch { }
        $script:LocTelemetry.DiskIo = [PSCustomObject]@{
            ReadMBps  = $readMBps
            WriteMBps = $writeMBps
            ReadIops  = $readIops
            WriteIops = $writeIops
        }

        # Network — primary IPv4 + bandwidth deltas
        $sendMbps = 0.0
        $recvMbps = 0.0
        try {
            $counters = Get-LocNetworkByteCounters
            if ($counters -and $script:LocNetPrev) {
                $dt = ($counters.At - $script:LocNetPrev.At).TotalSeconds
                if ($dt -gt 0.2) {
                    $dSent = [double]($counters.Sent - $script:LocNetPrev.Sent)
                    $dRecv = [double]($counters.Recv - $script:LocNetPrev.Recv)
                    if ($dSent -lt 0) { $dSent = 0 }
                    if ($dRecv -lt 0) { $dRecv = 0 }
                    $sendMbps = [math]::Round(($dSent * 8.0) / $dt / 1MB, 2)
                    $recvMbps = [math]::Round(($dRecv * 8.0) / $dt / 1MB, 2)
                }
            }
            if ($counters) { $script:LocNetPrev = $counters }
        }
        catch { }

        try {
            $nic = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -and (@($_.IPAddress) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^127\.' })
                } |
                Select-Object -First 1
            if ($nic) {
                $ipv4 = @($nic.IPAddress) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^127\.' } | Select-Object -First 1
                $script:LocTelemetry.Network = [PSCustomObject]@{
                    Connected = $true
                    IPv4      = [string]$ipv4
                    Adapter   = [string]$nic.Description
                    SendMbps  = $sendMbps
                    RecvMbps  = $recvMbps
                }
            }
            else {
                $script:LocTelemetry.Network = [PSCustomObject]@{
                    Connected = $false
                    IPv4      = $null
                    Adapter   = $null
                    SendMbps  = $sendMbps
                    RecvMbps  = $recvMbps
                }
            }
        }
        catch {
            $script:LocTelemetry.Network = [PSCustomObject]@{
                Connected = $false
                IPv4      = $null
                Adapter   = $null
                SendMbps  = $sendMbps
                RecvMbps  = $recvMbps
            }
        }

        # GPU identity (not live load)
        try {
            $gpu = Get-CimInstance -ClassName Win32_VideoController -Property Name, DriverVersion, AdapterRAM -ErrorAction Stop |
                Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic' } |
                Select-Object -First 1
            if (-not $gpu) {
                $gpu = Get-CimInstance -ClassName Win32_VideoController -Property Name, DriverVersion, AdapterRAM -ErrorAction Stop |
                    Select-Object -First 1
            }
            if ($gpu) {
                $ramGb = $null
                if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                    $ramGb = [math]::Round([double]$gpu.AdapterRAM / 1GB, 1)
                }
                $script:LocTelemetry.Gpu = [PSCustomObject]@{
                    Name          = [string]$gpu.Name
                    DriverVersion = [string]$gpu.DriverVersion
                    AdapterRAMGB  = $ramGb
                }
            }
            else {
                $script:LocTelemetry.Gpu = $null
            }
        }
        catch {
            $script:LocTelemetry.Gpu = $null
        }

        # Battery (null on desktops)
        try {
            $bat = Get-CimInstance -ClassName Win32_Battery -Property EstimatedChargeRemaining, BatteryStatus, Name -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($bat) {
                $script:LocTelemetry.Battery = [PSCustomObject]@{
                    ChargePct = if ($null -ne $bat.EstimatedChargeRemaining) { [int]$bat.EstimatedChargeRemaining } else { $null }
                    Status    = [string]$bat.BatteryStatus
                    Name      = [string]$bat.Name
                }
            }
            else {
                $script:LocTelemetry.Battery = $null
            }
        }
        catch {
            $script:LocTelemetry.Battery = $null
        }

        # Problem devices count (best-effort, never hang)
        try {
            $problemCount = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -and $_.Status -ne 'OK' }).Count
            $script:LocTelemetry.Devices = [PSCustomObject]@{
                ProblemCount = [int]$problemCount
            }
        }
        catch {
            $script:LocTelemetry.Devices = $null
        }

        # Host / uptime
        try {
            $boot = $os.LastBootUpTime
            $uptime = (Get-Date) - $boot
            $formatted = "{0}d {1:D2}h {2:D2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes
            $script:LocTelemetry.Host = [PSCustomObject]@{
                ComputerName    = if ($os.CSName) { [string]$os.CSName } else { $env:COMPUTERNAME }
                LastBoot        = $boot.ToString("yyyy-MM-dd HH:mm:ss")
                UptimeFormatted = $formatted
                PendingReboot   = (Test-LocPendingReboot)
            }
        }
        catch {
            $script:LocTelemetry.Host = [PSCustomObject]@{
                ComputerName    = $env:COMPUTERNAME
                LastBoot        = $null
                UptimeFormatted = "--"
                PendingReboot   = $false
            }
        }

        $script:LocTelemetry.Updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $script:LocTelemetryLastUpdate = Get-Date
    }
    catch {
        Write-LocLog -Module "CORE" -Action "TaskRunner" -Level "WARN" -Message $_.Exception.Message
    }
}

function Get-LocTelemetrySnapshot {
    param([bool]$Force = $false)

    $settings = Get-LocSettings
    $interval = 30
    if ($settings.taskIntervalSeconds) { $interval = [int]$settings.taskIntervalSeconds }
    if ($interval -lt 5) { $interval = 5 }

    $stale = $true
    if (-not $Force -and $script:LocTelemetryLastUpdate) {
        $stale = ((Get-Date) - $script:LocTelemetryLastUpdate).TotalSeconds -ge $interval
    }
    if ($Force -or $stale -or -not $script:LocTelemetry.Cpu) {
        Update-LocTelemetry
    }
    return Get-LocTelemetry
}

function Start-LocTaskRunner {
    $script:LocTaskRunnerEnabled = $true
    Update-LocTelemetry
    Write-LocLog -Module "CORE" -Action "TaskRunner" -Level "INFO" -Message "Task runner started (lightweight)"
}

function Stop-LocTaskRunner {
    $script:LocTaskRunnerEnabled = $false
}

function Test-LocTaskRunnerDue {
    param([datetime]$LastRun, [int]$IntervalSeconds)
    if (-not $script:LocTaskRunnerEnabled) { return $false }
    return ((Get-Date) - $LastRun).TotalSeconds -ge $IntervalSeconds
}
