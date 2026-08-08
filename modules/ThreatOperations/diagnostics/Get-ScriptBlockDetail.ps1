param([hashtable]$Params = @{})
. (Join-Path $PSScriptRoot '..\lib\ThreatRuleDefinitions.ps1')

try {
    $id = if ($Params.Id) { [string]$Params.Id } elseif ($Params.id) { [string]$Params.id } elseif ($Params.TransactionId) { [string]$Params.TransactionId } else { '' }
    if ([string]::IsNullOrWhiteSpace($id)) {
        return New-ApiResult -Success $false -Message 'Id or TransactionId required' -StatusCode 400
    }

    $rows = @(Get-LocThreatEventRecords -Max 50000)
    $match = $null
    foreach ($r in $rows) {
        if ([string]$r.id -eq $id -or [string]$r.transactionId -eq $id) {
            $match = $r
            break
        }
    }
    if (-not $match) {
        return New-ApiResult -Success $false -Message 'ScriptBlock event not found' -StatusCode 404
    }

    $hits = @($match.keywordHits)
    $playbooks = @(Get-LocThreatPlaybookHints -EventId ([int]$match.eventId) -KeywordHits $hits)
    return New-ApiResult -Success $true -Message 'ScriptBlock detail' -Data @{
        Id                     = [string]$match.id
        TransactionId          = [string]$match.transactionId
        EventId                = [int]$match.eventId
        Label                  = (Get-LocThreatEventLabel -EventId ([int]$match.eventId))
        Severity               = [string]$match.severity
        ComputerName           = [string]$match.computerName
        EnvironmentProfile     = [string]$match.environmentProfile
        Timestamp              = [string]$match.timestamp
        UserIdentity           = [string]$match.userIdentity
        ProcessName            = [string]$match.processName
        ServiceName            = [string]$match.serviceName
        ScriptBlockId          = [string]$match.scriptBlockId
        RawScriptBlockText     = [string]$match.rawScriptBlockText
        DecodedScriptBlockText = [string]$match.decodedScriptBlockText
        WasDecoded             = [bool]$match.wasDecoded
        KeywordHits            = $hits
        Playbooks              = @($playbooks)
    }
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
