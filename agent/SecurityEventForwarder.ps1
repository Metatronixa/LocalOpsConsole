# SecurityEventForwarder.ps1 - Batch security EventLog signals to console (read-only)
$script:LocThreatForwardLast = [datetime]::MinValue
$script:LocThreatForwardBookmarks = @{}

function Get-LocThreatWatchedEventIds {
    return @(1102, 4104, 4624, 4625, 4688, 4697, 4769, 7045)
}

function ConvertTo-LocThreatEventRow {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Eventing.Reader.EventRecord]$Record,
        [Parameter(Mandatory)][int]$EventId
    )
    $user = ''
    $process = ''
    $service = ''
    $scriptText = ''
    $scriptId = ''
    $encoded = $false
    try {
        $xml = [xml]$Record.ToXml()
        $data = @{}
        foreach ($n in @($xml.Event.EventData.Data)) {
            if ($n.Name) { $data[[string]$n.Name] = [string]$n.'#text' }
        }
        $user = if ($data['TargetUserName']) { $data['TargetUserName'] } elseif ($data['SubjectUserName']) { $data['SubjectUserName'] } else { '' }
        $process = if ($data['NewProcessName']) { $data['NewProcessName'] } elseif ($data['ProcessName']) { $data['ProcessName'] } elseif ($data['CommandLine']) { $data['CommandLine'] } else { '' }
        $service = if ($data['ServiceName']) { $data['ServiceName'] } elseif ($data['ServiceFileName']) { $data['ServiceFileName'] } else { '' }
        if ($EventId -eq 4104) {
            $scriptText = if ($data['ScriptBlockText']) { [string]$data['ScriptBlockText'] } else { '' }
            $scriptId = if ($data['ScriptBlockId']) { [string]$data['ScriptBlockId'] } else { '' }
            if ($scriptText -match '(?i)[A-Za-z0-9+/]{40,}={0,2}' -or $process -match '(?i)-enc(odedCommand)?') {
                $encoded = $true
            }
        }
    }
    catch {
        Write-Debug $_.Exception.Message
    }

    $sev = 'INFO'
    switch ($EventId) {
        1102 { $sev = 'HIGH' }
        4104 { $sev = 'MEDIUM' }
        4624 { $sev = 'INFO' }
        4625 { $sev = 'LOW' }
        4688 { $sev = 'INFO' }
        4697 { $sev = 'MEDIUM' }
        4769 { $sev = 'INFO' }
        7045 { $sev = 'MEDIUM' }
    }

    return [ordered]@{
        eventId            = $EventId
        transactionId      = [guid]::NewGuid().Guid
        timestamp          = $Record.TimeCreated.ToUniversalTime().ToString('o')
        severity           = $sev
        userIdentity       = $user
        processName        = $process
        serviceName        = $service
        scriptBlockId      = $scriptId
        rawScriptBlockText = $scriptText
        isEncoded          = $encoded
    }
}

function Get-LocThreatSecurityEvents {
    param([int]$MaxPerId = 40)
    $ids = @(Get-LocThreatWatchedEventIds)
    $rows = New-Object System.Collections.Generic.List[object]
    $logMap = @{
        1102 = 'Security'
        4624 = 'Security'
        4625 = 'Security'
        4688 = 'Security'
        4697 = 'Security'
        4769 = 'Security'
        4104 = 'Microsoft-Windows-PowerShell/Operational'
        7045 = 'System'
    }
    foreach ($id in $ids) {
        $logName = $logMap[$id]
        if (-not $logName) { continue }
        $since = $script:LocThreatForwardLast
        if ($since -eq [datetime]::MinValue) { $since = (Get-Date).AddMinutes(-5) }
        $filter = "*[System[(EventID=$id) and TimeCreated[@SystemTime>='{0}']]]" -f $since.ToUniversalTime().ToString('o')
        try {
            $query = New-Object System.Diagnostics.Eventing.Reader.EventLogQuery($logName, [System.Diagnostics.Eventing.Reader.PathType]::LogName, $filter)
            $reader = New-Object System.Diagnostics.Eventing.Reader.EventLogReader($query)
            $n = 0
            while ($n -lt $MaxPerId) {
                $rec = $reader.ReadEvent()
                if (-not $rec) { break }
                try {
                    $rows.Add((ConvertTo-LocThreatEventRow -Record $rec -EventId $id)) | Out-Null
                    $n++
                }
                finally { $rec.Dispose() }
            }
            $reader.Dispose()
        }
        catch {
            Write-Debug $_.Exception.Message
        }
    }
    return @($rows)
}

function Send-LocThreatTelemetryBatch {
    if (-not (Get-Command Invoke-AgentApi -ErrorAction SilentlyContinue)) { return }
    if (-not $script:AgentConfig -or -not $script:AgentConfig.AgentId) { return }

    $events = @(Get-LocThreatSecurityEvents)
    if ($events.Count -eq 0) {
        $script:LocThreatForwardLast = Get-Date
        return
    }

    $profile = 'StandaloneWorkgroup'
    if (Get-Command Get-LocAgentEnvironmentProfile -ErrorAction SilentlyContinue) {
        $profile = Get-LocAgentEnvironmentProfile
    }

    $body = [ordered]@{
        agentId            = [string]$script:AgentConfig.AgentId
        computerName       = $env:COMPUTERNAME
        environmentProfile = $profile
        batchTimestamp     = (Get-Date).ToUniversalTime().ToString('o')
        events             = @($events)
    }

    try {
        $resp = Invoke-AgentApi -Method POST -Path '/api/v1/fleet/threat-telemetry' -Body $body -Signed -TimeoutSec 30
        if ($resp.Success) {
            $script:LocThreatForwardLast = Get-Date
            Write-AgentLog ("Threat telemetry sent: {0} event(s)" -f $events.Count)
        }
        else {
            Write-AgentLog ("Threat telemetry rejected: {0}" -f $resp.Message) 'WARN'
        }
    }
    catch {
        Write-AgentLog ("Threat telemetry failed: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Pulse-LocThreatSecurityForwarder {
    param([int]$IntervalSec = 30)
    $now = Get-Date
    if (($now - $script:LocThreatForwardLast).TotalSeconds -lt $IntervalSec -and $script:LocThreatForwardLast -ne [datetime]::MinValue) {
        return
    }
    Send-LocThreatTelemetryBatch
}
