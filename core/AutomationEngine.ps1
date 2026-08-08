# core/AutomationEngine.ps1 - Automation history, rule invoke, and status

function Get-LocAutomationHistory {
    param([int]$Max = 50)
    $items = @()
    try {
        $auditPath = Join-Path (Get-LocRoot) "data\events\audit.jsonl"
        if (Test-Path $auditPath) {
            $lines = Get-Content $auditPath -Tail 400 -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                try {
                    $obj = $line | ConvertFrom-Json
                    if ($obj.Action -match '^(Automation|Playbook)') {
                        $items += $obj
                    }
                }
                catch { Write-Debug $_.Exception.Message }
            }
        }
    }
    catch { Write-Debug $_.Exception.Message }
    return @($items | Select-Object -Last $Max)
}

function Invoke-LocAutomationForRule {
    param(
        [object]$Rule,
        [object]$Incident,
        [Alias('Event')]
        [object]$LocEvent
    )

    if (-not $Rule -or -not $Rule.automation) { return }
    $auto = $Rule.automation
    if (-not (Test-LocAutomationEnabledForRule -Rule $Rule)) { return }

    # Local Event Intel only remediates This PC; fleet fan-out requires agent-scoped signals (Hub v2) or Run now.
    $pref = Get-LocPlaybookPrefEntry -RuleId $Rule.id
    $scope = if ($pref.HasPref) { $pref.Scope } else { "local" }
    if (-not (Test-LocPlaybookScopeIncludesLocal -Scope $scope)) {
        Add-LocEventAudit -Action "AutomationSkipped" -Detail "Scope excludes local host" -Data @{ RuleId = $Rule.id; Scope = $scope }
        return
    }

    $action = [string]$auto.action
    if ([string]::IsNullOrWhiteSpace($action)) { return }

    if (-not $script:LocAutomationHandlers.ContainsKey($action)) {
        Add-LocEventAudit -Action "AutomationSkipped" -Detail "Unknown action $action" -Data @{ RuleId = $Rule.id; IncidentId = $Incident.Id }
        return
    }

    $context = @{
        Rule     = $Rule
        Incident = $Incident
        Event    = $LocEvent
    }

    $result = & $script:LocAutomationHandlers[$action] $context
    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        Action    = $action
        Success   = [bool]$result.Success
        Message   = [string]$result.Message
        Operator  = "system"
    }

    $log = @()
    if ($Incident.AutomationLog) { $log = @($Incident.AutomationLog) }
    $log += $entry
    $Incident | Add-Member -NotePropertyName AutomationLog -NotePropertyValue $log -Force

    Add-LocTimelineEntry -Incident $Incident -Type "automation" -Title ("Automation: {0}" -f $action) `
        -Detail $entry.Message -Severity $Incident.Severity -Data @{ Success = $entry.Success } | Out-Null

    if ($result.Success -and $auto.verify -eq "service" -and $auto.service) {
        $verifyCtx = @{ Rule = $Rule; Incident = $Incident; Event = $Event }
        $verify = & $script:LocAutomationHandlers["verify-service"] $verifyCtx
        $vEntry = [PSCustomObject]@{
            Timestamp = (Get-Date).ToUniversalTime().ToString("o")
            Action    = "verify-service"
            Success   = [bool]$verify.Success
            Message   = [string]$verify.Message
            Operator  = "system"
        }
        $log += $vEntry
        $Incident | Add-Member -NotePropertyName AutomationLog -NotePropertyValue $log -Force
        Add-LocTimelineEntry -Incident $Incident -Type "automation" -Title "Automation: verify-service" `
            -Detail $vEntry.Message -Severity $Incident.Severity | Out-Null
        if (-not $verify.Success) { $result = $verify }
    }

    if ($auto.closeOnSuccess -and $result.Success) {
        Resolve-LocIncident -Id $Incident.Id -Operator "system" -Note ("Auto-closed after {0}" -f $action) | Out-Null
    }
    else {
        Write-LocIncidentFile -Incident $Incident -StatusFolder "active"
    }

    Add-LocEventAudit -Action "AutomationRan" -Detail $entry.Message -Operator "system" -Data @{
        RuleId     = $Rule.id
        IncidentId = $Incident.Id
        Action     = $action
        Success    = $entry.Success
        Scope      = $scope
    }
}

function Get-LocAutomationStatus {
    $rules = @(Get-LocAutomationRules)
    $history = @(Get-LocAutomationHistory -Max 25)
    return [PSCustomObject]@{
        Handlers      = @($script:LocAutomationHandlers.Keys)
        Rules         = $rules
        EnabledCount  = @($rules | Where-Object { $_.Enabled }).Count
        History       = $history
        Note          = 'Central hub: enable playbooks, set scope (This PC / Fleet / Both), then Run now. Event Intel auto still remediates This PC only when scope includes local. Agent Event Intel is Hub v2.'
    }
}
