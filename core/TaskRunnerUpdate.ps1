# core/TaskRunnerUpdate.ps1 - CPU / memory / disk / network telemetry refresh

function Update-LocTelemetryCore {
    # Fast CIM only - never Invoke-LocModuleAction / GetStatus here
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
    catch { Write-Debug $_.Exception.Message }
    $script:LocTelemetry.DiskIo = [PSCustomObject]@{
        ReadMBps  = $readMBps
        WriteMBps = $writeMBps
        ReadIops  = $readIops
        WriteIops = $writeIops
    }

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
    catch { Write-Debug $_.Exception.Message }

    try {
        $nic = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -and (@($_.IPAddress) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^127\.' })
            } |
            Select-Object -First 1
        if (-not $nic) {
            $nic = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -and (@($_.IPAddress) | Where-Object { $_ -match ':' -and $_ -notmatch '(?i)^::1$' })
                } |
                Select-Object -First 1
        }
        if ($nic) {
            $ipv4 = @($nic.IPAddress) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^127\.' } | Select-Object -First 1
            $v6 = Get-LocPrimaryIPv6 -Addresses @($nic.IPAddress)
            $script:LocTelemetry.Network = [PSCustomObject]@{
                Connected = $true
                IPv4      = if ($ipv4) { [string]$ipv4 } else { $null }
                IPv6      = if ($v6) { [string]$v6.Short } else { $null }
                IPv6Full  = if ($v6) { [string]$v6.Full } else { $null }
                Adapter   = [string]$nic.Description
                SendMbps  = $sendMbps
                RecvMbps  = $recvMbps
            }
        }
        else {
            $script:LocTelemetry.Network = [PSCustomObject]@{
                Connected = $false
                IPv4      = $null
                IPv6      = $null
                IPv6Full  = $null
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
            IPv6      = $null
            IPv6Full  = $null
            Adapter   = $null
            SendMbps  = $sendMbps
            RecvMbps  = $recvMbps
        }
    }

    return $os
}
