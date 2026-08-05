# core/EventEngine.ps1 - Orchestrates Event Intelligence pipeline

$script:LocEventIntelRunning = $false
$script:LocEventRing = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$script:LocEventIntelTimer = $null
$script:LocEventIntelLastIngest = $null
$script:LocEventIntelLastHealth = $null
$script:LocEventRingMax = 300

function Add-LocEventRing {
    param([object]$Event)
    [void]$script:LocEventRing.Insert(0, $Event)
    while ($script:LocEventRing.Count -gt $script:LocEventRingMax) {
        $script:LocEventRing.RemoveAt($script:LocEventRing.Count - 1)
    }
}

function Get-LocEventRing {
    param([int]$Max = 200)
    $list = [System.Collections.ArrayList]::new()
    $n = 0
    foreach ($item in @($script:LocEventRing.ToArray())) {
        if ($n -ge $Max) { break }
        [void]$list.Add($item)
        $n++
    }
    return @($list)
}

function Persist-LocEventRing {
    try {
        Save-LocRecentEvents -Events @($script:LocEventRing) -MaxKeep $script:LocEventRingMax
    }
    catch { }
}

function Invoke-LocEventIngest {
    param([Parameter(Mandatory)][object]$Event)

    Add-LocEventRing -Event $Event
    $script:LocEventIntelLastIngest = Get-Date

    $hits = Evaluate-LocEventRules -Event $Event
    foreach ($hit in $hits) {
        try {
            Process-LocRuleHit -Hit $hit | Out-Null
        }
        catch {
            Write-LocLog -Module "EVENTINTEL" -Action "Ingest" -Level "WARN" -Message $_.Exception.Message
        }
    }
}

function Invoke-LocEventIntelTick {
    if (-not $script:LocEventIntelRunning) { return }

    try {
        $drained = Drain-LocWatcherQueue -Max 80
        foreach ($ev in $drained) {
            Invoke-LocEventIngest -Event $ev
        }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Drain" -Level "WARN" -Message $_.Exception.Message
    }

    $now = Get-Date
    $interval = 30
    try {
        $s = Get-LocSettings
        if ($s.taskIntervalSeconds) { $interval = [int]$s.taskIntervalSeconds }
    }
    catch { }

    if (-not $script:LocEventIntelLastHealth -or ($now - $script:LocEventIntelLastHealth).TotalSeconds -ge $interval) {
        $script:LocEventIntelLastHealth = $now
        try {
            Test-LocRulesReload
            $healthEvents = Invoke-LocHealthCheckPass
            foreach ($he in $healthEvents) {
                Invoke-LocEventIngest -Event $he
            }
        }
        catch {
            Write-LocLog -Module "EVENTINTEL" -Action "Health" -Level "WARN" -Message $_.Exception.Message
        }
        Persist-LocEventRing
    }
}

function Start-LocEventIntelligence {
    if ($script:LocEventIntelRunning) { return }

    Initialize-LocEventStore
    Initialize-LocRuleEngine
    Initialize-LocHealthMonitor
    Import-LocNotificationChannels

    # Warm ring from disk
    try {
        foreach ($e in @(Get-LocStoredEvents -Max 200)) {
            [void]$script:LocEventRing.Add($e)
        }
    }
    catch { }

    Start-LocWatchManager
    $script:LocEventIntelRunning = $true
    $script:LocEventIntelLastTick = Get-Date

    Write-LocLog -Module "EVENTINTEL" -Action "Start" -Level "SUCCESS" -Message "Event Intelligence engine started"
    Add-LocEventAudit -Action "EngineStart" -Detail "Event Intelligence started"
}

function Pulse-LocEventIntelligence {
    # Called from the HTTP accept loop idle wait — same runspace as core functions
    if (-not $script:LocEventIntelRunning) { return }
    $now = Get-Date
    if ($script:LocEventIntelLastTick -and ($now - $script:LocEventIntelLastTick).TotalMilliseconds -lt 1500) {
        return
    }
    $script:LocEventIntelLastTick = $now
    try { Invoke-LocEventIntelTick } catch { }
}

function Stop-LocEventIntelligence {
    $script:LocEventIntelRunning = $false
    Stop-LocWatchManager
    Persist-LocEventRing
    Write-LocLog -Module "EVENTINTEL" -Action "Stop" -Level "INFO" -Message "Event Intelligence engine stopped"
    Add-LocEventAudit -Action "EngineStop" -Detail "Event Intelligence stopped"
}

function Get-LocEventIntelStatus {
    $watch = Get-LocWatcherStatus
    return [PSCustomObject]@{
        Running      = $script:LocEventIntelRunning
        LastIngest   = if ($script:LocEventIntelLastIngest) { $script:LocEventIntelLastIngest.ToUniversalTime().ToString("o") } else { $null }
        LastHealth   = if ($script:LocEventIntelLastHealth) { $script:LocEventIntelLastHealth.ToUniversalTime().ToString("o") } else { $null }
        RingCount    = $script:LocEventRing.Count
        RulesLoaded  = @($script:LocRules).Count
        Watchers     = $watch
        Automation   = Get-LocAutomationStatus
    }
}

function Get-LocAlertHeatmap {
    $alerts = @(Get-LocStoredAlerts)
    $incidents = @(Get-LocIncidentFiles -Status "active")
    $cats = @{
        security = 0
        network  = 0
        storage  = 0
        printers = 0
        printing = 0
        services = 0
        system   = 0
        updates  = 0
    }
    foreach ($a in $alerts) {
        $c = ([string]$a.Category).ToLower()
        if ($c -eq "printing") { $c = "printers" }
        if ($cats.ContainsKey($c)) { $cats[$c]++ } else { $cats[$c] = 1 }
    }
    foreach ($i in $incidents) {
        $c = ([string]$i.Category).ToLower()
        if ($c -eq "printing") { $c = "printers" }
        if ($cats.ContainsKey($c)) { $cats[$c]++ } else { $cats[$c] = 1 }
    }

    return [PSCustomObject]@{
        Security = $cats["security"]
        Network  = $cats["network"]
        Storage  = $cats["storage"]
        Printing = $cats["printers"]
        Services = $cats["services"]
        System   = $cats["system"]
        Updates  = $cats["updates"]
        Updated  = (Get-Date).ToUniversalTime().ToString("o")
    }
}
