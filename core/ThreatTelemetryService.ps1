# ThreatTelemetryService.ps1 - Validate + ingest threat telemetry batches
function Test-LocThreatTelemetryBatch {
    param([hashtable]$Batch)
    if (-not $Batch) { return 'Batch required' }
    $agentId = [string]$Batch['agentId']
    $computer = [string]$Batch['computerName']
    $profile = [string]$Batch['environmentProfile']
    $events = @($Batch['events'])
    if ([string]::IsNullOrWhiteSpace($agentId)) { return 'agentId required' }
    if ([string]::IsNullOrWhiteSpace($computer)) { return 'computerName required' }
    if ([string]::IsNullOrWhiteSpace($profile)) { return 'environmentProfile required' }
    $allowed = @(Get-LocThreatAllowedProfiles)
    if ($allowed -notcontains $profile) { return "Invalid environmentProfile: $profile" }
    if (-not $Batch['batchTimestamp']) { return 'batchTimestamp required' }
    if ($events.Count -eq 0) { return 'events array required' }
    $ids = @(Get-LocThreatAllowedEventIds)
    foreach ($ev in $events) {
        $ht = ConvertTo-LocThreatEventHashtable -Event $ev
        if ($null -eq $ht['eventId']) { return 'event.eventId required' }
        $eid = [int]$ht['eventId']
        if ($ids -notcontains $eid) { return "Unsupported eventId: $eid" }
        if (-not $ht['transactionId']) { return 'event.transactionId required' }
        if (-not $ht['timestamp']) { return 'event.timestamp required' }
        if (-not $ht['severity']) { return 'event.severity required' }
    }
    return $null
}

function ConvertTo-LocThreatEventHashtable {
    param($Event)
    if ($Event -is [hashtable]) { return $Event }
    $h = @{}
    foreach ($p in $Event.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Invoke-LocThreatTelemetryIngest {
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][hashtable]$Batch
    )
    $err = Test-LocThreatTelemetryBatch -Batch $Batch
    if ($err) {
        return New-ApiResult -Success $false -Message $err -StatusCode 400
    }

    $profile = [string]$Batch['environmentProfile']
    $computer = [string]$Batch['computerName']
    $batchAgent = [string]$Batch['agentId']
    if ($batchAgent -and $batchAgent -ne $AgentId) {
        return New-ApiResult -Success $false -Message 'agentId mismatch' -StatusCode 403
    }

    $processed = 0
    $failBurst = @{}
    foreach ($raw in @($Batch['events'])) {
        $ev = ConvertTo-LocThreatEventHashtable -Event $raw
        $eid = [int]$ev['eventId']
        if ($eid -eq 4625) {
            $key = [string]$ev['userIdentity']
            if (-not $failBurst.ContainsKey($key)) { $failBurst[$key] = 0 }
            $failBurst[$key] = [int]$failBurst[$key] + 1
        }
    }

    foreach ($raw in @($Batch['events'])) {
        $ev = ConvertTo-LocThreatEventHashtable -Event $raw
        $eid = [int]$ev['eventId']
        $rawScript = [string]$ev['rawScriptBlockText']
        $isEnc = [bool]$ev['isEncoded']
        $decode = Invoke-LocScriptBlockDecode -RawText $rawScript -IsEncoded $isEnc
        $burst = 0
        if ($eid -eq 4625) {
            $burst = [int]$failBurst[[string]$ev['userIdentity']]
        }
        $sev = Resolve-LocThreatSeverity -EventId $eid -EnvironmentProfile $profile `
            -BaseSeverity ([string]$ev['severity']) `
            -ProcessName ([string]$ev['processName']) `
            -ServiceName ([string]$ev['serviceName']) `
            -HighRiskScript ([bool]$decode.HighRisk) `
            -FailedLogonBurst $burst

        $record = @{
            id                   = [guid]::NewGuid().Guid
            agentId              = $AgentId
            computerName         = $computer
            environmentProfile   = $profile
            eventId              = $eid
            transactionId        = [string]$ev['transactionId']
            timestamp            = [string]$ev['timestamp']
            severity             = $sev
            userIdentity         = [string]$ev['userIdentity']
            processName          = [string]$ev['processName']
            serviceName          = [string]$ev['serviceName']
            scriptBlockId        = [string]$ev['scriptBlockId']
            rawScriptBlockText   = [string]$decode.RawText
            decodedScriptBlockText = [string]$decode.DecodedText
            wasDecoded           = [bool]$decode.WasDecoded
            keywordHits          = @($decode.KeywordHits)
            ingestedUtc          = (Get-Date).ToUniversalTime().ToString('o')
        }
        Add-LocThreatEventRecord -Record $record
        $processed++
    }

    try { Invoke-LocThreatRingPrune } catch { Write-Debug $_.Exception.Message }

    return New-ApiResult -Success $true -Message 'Threat telemetry ingested' -Data @{
        Processed = $processed
    }
}
