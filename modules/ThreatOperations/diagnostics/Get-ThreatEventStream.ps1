param([hashtable]$Params = @{})
. (Join-Path $PSScriptRoot '..\lib\ThreatRuleDefinitions.ps1')

try {
    $max = 200
    if ($Params.Max) { [void][int]::TryParse([string]$Params.Max, [ref]$max) }
    if ($max -lt 1) { $max = 1 }
    if ($max -gt 1000) { $max = 1000 }

    $profile = if ($Params.environmentProfile) { [string]$Params.environmentProfile } elseif ($Params.EnvironmentProfile) { [string]$Params.EnvironmentProfile } else { '' }
    $severity = if ($Params.severity) { [string]$Params.severity } elseif ($Params.Severity) { [string]$Params.Severity } else { '' }
    $eventId = $null
    if ($Params.eventId) { $eventId = [int]$Params.eventId } elseif ($Params.EventId) { $eventId = [int]$Params.EventId }
    $search = if ($Params.search) { [string]$Params.search } elseif ($Params.Search) { [string]$Params.Search } else { '' }

    $rows = @(Get-LocThreatEventRecords -Max 50000)
    $filtered = New-Object System.Collections.Generic.List[object]
    foreach ($r in $rows) {
        if ($profile -and [string]$r.environmentProfile -ne $profile) { continue }
        if ($severity -and [string]$r.severity -ne $severity.ToUpperInvariant()) { continue }
        if ($null -ne $eventId -and [int]$r.eventId -ne $eventId) { continue }
        if ($search) {
            $blob = (@(
                    $r.computerName, $r.userIdentity, $r.processName, $r.serviceName,
                    $r.rawScriptBlockText, $r.decodedScriptBlockText
                ) -join ' ')
            if ($blob -notmatch [regex]::Escape($search)) { continue }
        }
        $filtered.Add([PSCustomObject]@{
                Id                 = $r.id
                EventId            = [int]$r.eventId
                Label              = (Get-LocThreatEventLabel -EventId ([int]$r.eventId))
                Severity           = [string]$r.severity
                ComputerName       = [string]$r.computerName
                EnvironmentProfile = [string]$r.environmentProfile
                Timestamp          = [string]$r.timestamp
                UserIdentity       = [string]$r.userIdentity
                ProcessName        = [string]$r.processName
                HasScriptBlock     = -not [string]::IsNullOrWhiteSpace([string]$r.rawScriptBlockText)
                KeywordHits        = @($r.keywordHits)
            }) | Out-Null
    }

    $ordered = @($filtered | Sort-Object Timestamp -Descending | Select-Object -First $max)
    return New-ApiResult -Success $true -Message 'Threat event stream' -Data @{
        Items = @($ordered)
        Count = $ordered.Count
    }
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
