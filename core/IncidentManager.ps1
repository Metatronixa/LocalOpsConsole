# core/IncidentManager.ps1 - Create, update, resolve incidents

function New-LocIncident {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$RuleId = "",
        [string]$Category = "system",
        [string]$Severity = "Warning",
        [int]$Score = 50,
        [string]$CorrelationKey = "",
        [Alias('Event')]
        [object]$LocEvent = $null,
        [object]$Rule = $null,
        [string[]]$RelatedRules = @()
    )

    $null = $Rule
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $inc = [PSCustomObject]@{
        Id              = [guid]::NewGuid().ToString()
        Title           = $Title
        Status          = "Open"
        Severity        = $Severity
        Score           = $Score
        Category        = $Category
        RuleId          = $RuleId
        CorrelationKey  = $CorrelationKey
        RelatedRules    = @($RelatedRules)
        EventCount      = 1
        CreatedAt       = $now
        UpdatedAt       = $now
        ResolvedAt      = $null
        Acknowledged    = $false
        AcknowledgedAt  = $null
        Timeline        = @()
        LastEvent       = $LocEvent
        AutomationLog   = @()
    }

    $detail = if ($LocEvent -and $LocEvent.Message) { [string]$LocEvent.Message } else { "Incident opened" }
    Add-LocTimelineEntry -Incident $inc -Type "detection" -Title $Title -Detail $detail -Severity $Severity | Out-Null
    Write-LocIncidentFile -Incident $inc -StatusFolder "active"
    Add-LocEventAudit -Action "IncidentOpened" -Detail $Title -Data @{ Id = $inc.Id; RuleId = $RuleId; Score = $Score }
    return $inc
}

function Update-LocIncident {
    param(
        [Parameter(Mandatory)][object]$Incident,
        [Alias('Event')]
        [object]$LocEvent = $null,
        [string]$Severity = "",
        [int]$Score = -1,
        [string]$TimelineTitle = "",
        [string]$TimelineDetail = ""
    )

    $Incident.UpdatedAt = (Get-Date).ToUniversalTime().ToString("o")
    if ($LocEvent) {
        $Incident.EventCount = [int]$Incident.EventCount + 1
        $Incident.LastEvent = $LocEvent
        $title = if ($TimelineTitle) { $TimelineTitle } elseif ($LocEvent.Message) { [string]$LocEvent.Message } else { "Related event" }
        $detail = if ($TimelineDetail) { $TimelineDetail } else { "$($LocEvent.Source) EventID $($LocEvent.EventID)" }
        Add-LocTimelineEntry -Incident $Incident -Type "event" -Title $title -Detail $detail -Severity $(if ($Severity) { $Severity } else { $LocEvent.Severity }) | Out-Null
    }
    elseif ($TimelineTitle) {
        Add-LocTimelineEntry -Incident $Incident -Type "note" -Title $TimelineTitle -Detail $TimelineDetail -Severity $Severity | Out-Null
    }

    if ($Severity) { $Incident.Severity = $Severity }
    if ($Score -ge 0) { $Incident.Score = $Score }

    Write-LocIncidentFile -Incident $Incident -StatusFolder "active"
    return $Incident
}

function Get-LocIncidentById {
    param([Parameter(Mandatory)][string]$Id)
    foreach ($folder in @("active", "resolved", "archive")) {
        $path = Join-Path (Join-Path (Get-LocIncidentDir) $folder) "$Id.json"
        if (Test-Path $path) {
            return Read-LocIncidentFile -Path $path
        }
    }
    return $null
}

function Resolve-LocIncident {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Operator = "operator",
        [string]$Note = "Resolved"
    )
    $inc = Get-LocIncidentById -Id $Id
    if (-not $inc) {
        return New-ApiResult -Success $false -Message "Incident not found" -StatusCode 404
    }
    if ($inc.Status -eq "Resolved") {
        return New-ApiResult -Success $true -Message "Already resolved" -Data $inc
    }

    $inc.Status = "Resolved"
    $inc.ResolvedAt = (Get-Date).ToUniversalTime().ToString("o")
    $inc.UpdatedAt = $inc.ResolvedAt
    Add-LocTimelineEntry -Incident $inc -Type "resolved" -Title "Resolved" -Detail $Note -Severity $inc.Severity -Data @{ Operator = $Operator } | Out-Null

    Remove-LocIncidentFile -Id $Id -StatusFolder "active"
    Write-LocIncidentFile -Incident $inc -StatusFolder "resolved"
    Add-LocEventAudit -Action "IncidentResolved" -Detail $Note -Operator $Operator -Data @{ Id = $Id }

    return New-ApiResult -Success $true -Message "Incident resolved" -Data $inc
}

function Acknowledge-LocIncident {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Operator = "operator"
    )
    $inc = Get-LocIncidentById -Id $Id
    if (-not $inc) {
        return New-ApiResult -Success $false -Message "Incident not found" -StatusCode 404
    }
    $inc.Acknowledged = $true
    $inc.AcknowledgedAt = (Get-Date).ToUniversalTime().ToString("o")
    $inc.UpdatedAt = $inc.AcknowledgedAt
    Add-LocTimelineEntry -Incident $inc -Type "ack" -Title "Acknowledged" -Detail "Acknowledged by $Operator" -Severity $inc.Severity | Out-Null
    $folder = if ($inc.Status -eq "Resolved") { "resolved" } else { "active" }
    Write-LocIncidentFile -Incident $inc -StatusFolder $folder
    return New-ApiResult -Success $true -Message "Acknowledged" -Data $inc
}

function Get-LocIncidentSummary {
    $active = @(Get-LocIncidentFiles -Status "active")
    $resolved = @(Get-LocIncidentFiles -Status "resolved")
    $today = (Get-Date).Date
    $resolvedToday = @($resolved | Where-Object {
            try { [datetime]::Parse([string]$_.ResolvedAt).ToLocalTime().Date -eq $today } catch { $false }
        }).Count

    return [PSCustomObject]@{
        Open           = $active.Count
        Critical       = @($active | Where-Object { $_.Severity -eq "Critical" }).Count
        Warnings       = @($active | Where-Object { $_.Severity -eq "Warning" }).Count
        Information    = @($active | Where-Object { $_.Severity -eq "Information" }).Count
        ResolvedToday  = $resolvedToday
        Incidents      = $active
    }
}

function Process-LocRuleHit {
    param(
        [Parameter(Mandatory)][object]$Hit
    )

    $rule = $Hit.Rule
    $locEvent = $Hit.Event
    $title = if ($rule.incident) { [string]$rule.incident } else { [string]$rule.id }
    $category = if ($rule.category) { [string]$rule.category } else { [string]$locEvent.Category }
    $corrKey = Resolve-LocCorrelationKey -Rule $rule -Event $locEvent

    Register-LocRuleFire -RuleId ([string]$rule.id) -IncidentTitle $title

    $existing = Find-LocOpenIncidentForRule -RuleId ([string]$rule.id) -Title $title -CorrelationKey $corrKey
    $scoreInfo = Compute-LocIncidentScore -Incident ([PSCustomObject]@{ Severity = $rule.severity; Category = $category }) -Rule $rule -Recurrence ([int]$Hit.HitCount) -ChainLength 1

    if ($existing) {
        $existing = Update-LocIncident -Incident $existing -Event $locEvent -Severity $scoreInfo.Severity -Score $scoreInfo.Score `
            -TimelineTitle $title -TimelineDetail ("Hit count: {0} in {1}s" -f $Hit.HitCount, $Hit.WindowSecs)
        Invoke-LocIncidentNotify -Incident $existing -Rule $rule -IsNew $false
        Invoke-LocAutomationForRule -Rule $rule -Incident $existing -Event $locEvent
        return $existing
    }

    $inc = New-LocIncident -Title $title -RuleId ([string]$rule.id) -Category $category `
        -Severity $scoreInfo.Severity -Score $scoreInfo.Score -CorrelationKey $corrKey -Event $locEvent -Rule $rule

    # Correlation chains may escalate / open a higher-level incident
    $chains = Test-LocCorrelationChains -TriggeredRuleId ([string]$rule.id)
    foreach ($c in $chains) {
        $chain = $c.Chain
        $chainKey = "chain|$($chain.id)"
        $chainInc = Find-LocOpenIncidentForRule -RuleId $chain.id -Title $chain.title -CorrelationKey $chainKey
        $chainScore = Compute-LocIncidentScore -Incident ([PSCustomObject]@{ Severity = $chain.severity; Category = $chain.category }) `
            -Rule $chain -ChainLength (@($c.FiredRules).Count) -Recurrence ([int]$c.HitCount)
        if ($chainInc) {
            Update-LocIncident -Incident $chainInc -Event $locEvent -Severity $chainScore.Severity -Score $chainScore.Score `
                -TimelineTitle $chain.title -TimelineDetail ("Chain rules: {0}" -f ($c.FiredRules -join ", ")) | Out-Null
        }
        else {
            $chainInc = New-LocIncident -Title $chain.title -RuleId $chain.id -Category $chain.category `
                -Severity $chainScore.Severity -Score $chainScore.Score -CorrelationKey $chainKey -Event $locEvent `
                -RelatedRules @($c.FiredRules)
            Invoke-LocIncidentNotify -Incident $chainInc -Rule $chain -IsNew $true
        }
    }

    Invoke-LocIncidentNotify -Incident $inc -Rule $rule -IsNew $true
    Invoke-LocAutomationForRule -Rule $rule -Incident $inc -Event $locEvent
    return $inc
}
