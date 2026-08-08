# core/WatchManager.ps1 - EventLogWatcher subscriptions + normalize

$script:LocWatchers = [System.Collections.ArrayList]::new()
$script:LocWatcherJobs = [System.Collections.ArrayList]::new()
$script:LocEventQueue = $null
$script:LocWatcherStatus = [System.Collections.Hashtable]::Synchronized(@{})

function Get-LocWatcherDefinitions {
    $defs = @(
        @{ Name = "Security"; LogName = "Security"; Category = "security" },
        @{ Name = "System"; LogName = "System"; Category = "system" },
        @{ Name = "Application"; LogName = "Application"; Category = "system" },
        @{ Name = "Defender"; LogName = "Microsoft-Windows-Windows Defender/Operational"; Category = "security" },
        @{ Name = "PowerShell"; LogName = "Microsoft-Windows-PowerShell/Operational"; Category = "security" },
        @{ Name = "PrintService"; LogName = "Microsoft-Windows-PrintService/Operational"; Category = "printers" },
        @{ Name = "DnsClient"; LogName = "Microsoft-Windows-DNS-Client/Operational"; Category = "network" },
        @{ Name = "WindowsUpdate"; LogName = "Microsoft-Windows-WindowsUpdateClient/Operational"; Category = "updates" },
        @{ Name = "TaskScheduler"; LogName = "Microsoft-Windows-TaskScheduler/Operational"; Category = "system" },
        @{ Name = "TerminalServices"; LogName = "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"; Category = "security" }
    )

    $ei = Get-LocEventIntelSettings
    if ($ei.sysmonOptional) {
        $defs += @{ Name = "Sysmon"; LogName = "Microsoft-Windows-Sysmon/Operational"; Category = "security"; Optional = $true }
    }
    return $defs
}

function Convert-LocWinEventSeverity {
    param($Record)
    try {
        $level = [int]$Record.Level
        switch ($level) {
            1 { return "Critical" }
            2 { return "Critical" }
            3 { return "Warning" }
            default { return "Information" }
        }
    }
    catch { return "Information" }
}

function Test-LocNoisyEventId {
    param([string]$SourceName, [int]$EventId)
    # High-volume / low-signal IDs that blow up the ring and JSON store
    $noise = @{
        "PowerShell"      = @(4104, 4105, 4106)  # scriptblock / module logging
        "DnsClient"       = @(1014)              # name resolution timeout flood
        "TaskScheduler"   = @(100, 102, 110, 200, 201) # routine task start/stop
        "WindowsUpdate"   = @(19, 43)            # routine install chatter
    }
    if ($noise.ContainsKey($SourceName) -and $noise[$SourceName] -contains $EventId) {
        return $true
    }
    return $false
}

function Convert-LocEventRecordToNormalized {
    param(
        $Record,
        [string]$SourceName,
        [string]$Category = "system"
    )
    if (-not $Record) { return $null }

    $eventId = 0
    try { $eventId = [int]$Record.Id } catch { Write-Debug $_.Exception.Message }
    if (Test-LocNoisyEventId -SourceName $SourceName -EventId $eventId) { return $null }

    $msg = ""
    try { $msg = [string]$Record.FormatDescription() } catch {
        try { $msg = [string]$Record.Message } catch { $msg = "" }
    }
    if ($msg.Length -gt 400) { $msg = $msg.Substring(0, 400) }

    $ts = Get-Date
    try { $ts = [datetime]$Record.TimeCreated } catch { Write-Debug $_.Exception.Message }

    $data = @{}
    try {
        if ($Record.Properties) {
            $i = 0
            foreach ($p in @($Record.Properties)) {
                $val = [string]$p.Value
                if ($val.Length -gt 160) { $val = $val.Substring(0, 160) }
                $data["p$i"] = $val
                $i++
                if ($i -ge 8) { break }
            }
        }
    }
    catch { Write-Debug $_.Exception.Message }

    return New-LocNormalizedEvent -Source $SourceName -EventID $eventId -Severity (Convert-LocWinEventSeverity -Record $Record) `
        -Category $Category -Message $msg -Data $data -Timestamp $ts
}

function Initialize-LocWatchManager {
    if (-not $script:LocEventQueue) {
        $script:LocEventQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    }
    $script:LocWatchers.Clear()
    $script:LocWatcherJobs.Clear()
    $script:LocWatcherStatus.Clear()
}

function Start-LocWatchManager {
    Initialize-LocWatchManager
    $queue = $script:LocEventQueue

    foreach ($def in Get-LocWatcherDefinitions) {
        $logName = [string]$def.LogName
        $name = [string]$def.Name
        $category = [string]$def.Category
        $optional = [bool]$def.Optional

        try {
            # Verify log exists
            $null = Get-WinEvent -ListLog $logName -ErrorAction Stop
        }
        catch {
            $script:LocWatcherStatus[$name] = "unavailable"
            if (-not $optional) {
                Write-LocLog -Module "EVENTINTEL" -Action "Watcher" -Level "WARN" -Message "Log unavailable: $logName"
            }
            continue
        }

        try {
            # Prefer warnings/errors; PowerShell Operational is especially chatty at Level=4
            $xpath = "*[System[(Level=1 or Level=2 or Level=3)]]"
            if ($name -eq "Security") {
                # Security uses Audit Success/Failure, not classic Level the same way — keep broad
                $xpath = "*"
            }
            $query = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery(
                $logName,
                [System.Diagnostics.Eventing.Reader.PathType]::LogName,
                $xpath
            )
            $watcher = New-Object System.Diagnostics.Eventing.Reader.EventLogWatcher($query)

            $action = {
                try {
                    $sourceArgs = $Event.SourceEventArgs
                    if (-not $sourceArgs -or -not $sourceArgs.EventRecord) { return }
                    $payload = [PSCustomObject]@{
                        SourceName = $Event.MessageData.SourceName
                        Category   = $Event.MessageData.Category
                        Record     = $sourceArgs.EventRecord
                    }
                    [void]$Event.MessageData.Queue.Enqueue($payload)
                }
                catch { Write-Debug $_.Exception.Message }
            }

            $msgData = New-Object PSObject -Property @{
                Queue      = $queue
                SourceName = $name
                Category   = $category
            }

            $job = Register-ObjectEvent -InputObject $watcher -EventName "EventRecordWritten" `
                -Action $action -MessageData $msgData -ErrorAction Stop

            $watcher.Enabled = $true
            [void]$script:LocWatchers.Add($watcher)
            [void]$script:LocWatcherJobs.Add($job)
            $script:LocWatcherStatus[$name] = "watching"
            Write-LocLog -Module "EVENTINTEL" -Action "Watcher" -Level "INFO" -Message "Watching $logName"
        }
        catch {
            $script:LocWatcherStatus[$name] = "error"
            Write-LocLog -Module "EVENTINTEL" -Action "Watcher" -Level "WARN" -Message "Failed $logName : $($_.Exception.Message)"
        }
    }
}

function Stop-LocWatchManager {
    foreach ($w in @($script:LocWatchers)) {
        try { $w.Enabled = $false } catch { Write-Debug $_.Exception.Message }
        try { $w.Dispose() } catch { Write-Debug $_.Exception.Message }
    }
    $script:LocWatchers.Clear()

    foreach ($j in @($script:LocWatcherJobs)) {
        try {
            Unregister-Event -SourceIdentifier $j.Name -ErrorAction SilentlyContinue
            Remove-Job -Id $j.Id -Force -ErrorAction SilentlyContinue
        }
        catch { Write-Debug $_.Exception.Message }
    }
    $script:LocWatcherJobs.Clear()
    $script:LocWatcherStatus.Clear()
}

function Get-LocWatcherStatus {
    $map = @{}
    foreach ($k in @($script:LocWatcherStatus.Keys)) {
        $map[$k] = $script:LocWatcherStatus[$k]
    }
    return [PSCustomObject]@{
        Watchers = $map
        Active   = @($script:LocWatchers).Count
        QueueLen = if ($script:LocEventQueue) { $script:LocEventQueue.Count } else { 0 }
    }
}

function Drain-LocWatcherQueue {
    param([int]$Max = 100)
    $out = @()
    if (-not $script:LocEventQueue) { return $out }
    $item = $null
    $n = 0
    while ($n -lt $Max -and $script:LocEventQueue.TryDequeue([ref]$item)) {
        try {
            $norm = Convert-LocEventRecordToNormalized -Record $item.Record -SourceName $item.SourceName -Category $item.Category
            try { $item.Record.Dispose() } catch { Write-Debug $_.Exception.Message }
            if ($norm) { $out += $norm }
        }
        catch { Write-Debug $_.Exception.Message }
        $n++
    }
    return $out
}
