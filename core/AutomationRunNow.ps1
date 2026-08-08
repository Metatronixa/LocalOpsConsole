# core/AutomationRunNow.ps1 - Manual and fleet-auto playbook execution

function Invoke-LocPlaybookRunNow {
    param(
        [Parameter(Mandatory)][string]$RuleId,
        [string[]]$AgentIds = $null,
        [string]$Operator = "operator"
    )
    $id = $RuleId.Trim()
    $rule = $null
    if (Get-Command Get-LocRules -ErrorAction SilentlyContinue) {
        $rule = @(Get-LocRules) | Where-Object { $_.id -eq $id } | Select-Object -First 1
    }
    if (-not $rule -or -not $rule.automation) {
        return New-ApiResult -Success $false -Message "Playbook not found: $id" -StatusCode 404
    }

    $pref = Get-LocPlaybookPrefEntry -RuleId $id
    $scope = $pref.Scope
    if (-not $pref.HasPref) { $scope = "local" }
    $map = Get-LocPlaybookFleetMapping -Rule $rule
    $targets = @()
    $action = [string]$rule.automation.action

    if (Test-LocPlaybookScopeIncludesLocal -Scope $scope) {
        if ($script:LocAutomationHandlers.ContainsKey($action)) {
            $ctx = @{ Rule = $rule; Incident = $null; Event = $null }
            $result = & $script:LocAutomationHandlers[$action] $ctx
            $targets += [PSCustomObject]@{
                Target    = "local"
                AgentId   = $null
                Status    = $(if ($result.Success) { "Completed" } else { "Failed" })
                Success   = [bool]$result.Success
                Message   = [string]$result.Message
                CommandId = $null
                Type      = $action
            }
            Add-LocEventAudit -Action "AutomationRan" -Detail ("RunNow local: {0}" -f $result.Message) -Operator $Operator -Data @{
                RuleId  = $id
                Target  = "local"
                Action  = $action
                Success = [bool]$result.Success
            }
        }
        else {
            $targets += [PSCustomObject]@{
                Target = "local"; AgentId = $null; Status = "Failed"; Success = $false
                Message = "Unknown action $action"; CommandId = $null; Type = $action
            }
        }
    }

    if (Test-LocPlaybookScopeIncludesFleet -Scope $scope) {
        if ($action -eq "notify-only") {
            $targets += [PSCustomObject]@{
                Target = "fleet"; AgentId = $null; Status = "Completed"; Success = $true
                Message = "Notify-only: no fleet command queued"; CommandId = $null; Type = "notify-only"
            }
            Add-LocEventAudit -Action "AutomationRan" -Detail "RunNow fleet notify-only (no command)" -Operator $Operator -Data @{
                RuleId = $id; Target = "fleet"; Action = $action; Success = $true
            }
        }
        elseif (-not $map.SupportsFleet) {
            $targets += [PSCustomObject]@{
                Target = "fleet"; AgentId = $null; Status = "Failed"; Success = $false
                Message = "Action does not map to a fleet command"; CommandId = $null; Type = $action
            }
        }
        elseif (-not (Get-Command Queue-LocFleetCommand -ErrorAction SilentlyContinue)) {
            $targets += [PSCustomObject]@{
                Target = "fleet"; AgentId = $null; Status = "Failed"; Success = $false
                Message = "Fleet queue unavailable"; CommandId = $null; Type = $map.FleetCommand
            }
        }
        else {
            $agentList = Resolve-LocPlaybookFleetAgentIds -AgentIds $pref.AgentIds -OverrideAgentIds $AgentIds
            if ($agentList.Count -eq 0) {
                $targets += [PSCustomObject]@{
                    Target = "fleet"; AgentId = $null; Status = "Failed"; Success = $false
                    Message = "No online fleet agents in scope"; CommandId = $null; Type = $map.FleetCommand
                }
            }
            else {
                foreach ($aid in $agentList) {
                    $q = Queue-LocFleetCommand -AgentId $aid -Type $map.FleetCommand -Payload $map.Payload
                    $ok = [bool]$q.Success
                    $cmdId = if ($ok -and $q.Data -and $q.Data.Id) { [string]$q.Data.Id } else { $null }
                    $targets += [PSCustomObject]@{
                        Target    = "fleet"
                        AgentId   = $aid
                        Status    = $(if ($ok) { "Pending" } else { "Failed" })
                        Success   = $ok
                        Message   = $(if ($ok) { "Queued $($map.FleetCommand)" } else { [string]$q.Message })
                        CommandId = $cmdId
                        Type      = $map.FleetCommand
                    }
                    Add-LocEventAudit -Action "AutomationRan" -Detail ("RunNow fleet {0}: {1}" -f $aid, $map.FleetCommand) -Operator $Operator -Data @{
                        RuleId    = $id
                        AgentId   = $aid
                        Action    = $map.FleetCommand
                        Success   = $ok
                        CommandId = $cmdId
                    }
                }
            }
        }
    }

    $anyOk = @($targets | Where-Object { $_.Success }).Count -gt 0
    $msg = if ($targets.Count -eq 0) {
        "Nothing to run for scope=$scope"
    } else {
        "Run now: {0} target(s)" -f $targets.Count
    }
    return New-ApiResult -Success ($anyOk -or ($targets.Count -eq 0 -and $scope -eq 'local')) -Message $msg -Data ([PSCustomObject]@{
            RuleId   = $id
            Scope    = $scope
            Targets  = @($targets)
            Mapping  = $map
        }) -StatusCode $(if ($anyOk -or $targets.Count -eq 0) { 200 } else { 400 })
}

function Test-LocPlaybookFleetAutoEnabled {
    param([string]$RuleId)
    $pref = Get-LocPlaybookPrefEntry -RuleId $RuleId
    if (-not $pref.HasPref -or -not $pref.Enabled) { return $false }
    return (Test-LocPlaybookScopeIncludesFleet -Scope $pref.Scope)
}

function Invoke-LocPlaybookFleetAutoForAgent {
    param(
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][string]$AgentId,
        [string]$Reason = "fleet-auto"
    )
    if (-not (Test-LocPlaybookFleetAutoEnabled -RuleId $RuleId)) { return $null }
    $rule = $null
    if (Get-Command Get-LocRules -ErrorAction SilentlyContinue) {
        $rule = @(Get-LocRules) | Where-Object { $_.id -eq $RuleId } | Select-Object -First 1
    }
    if (-not $rule) { return $null }
    $pref = Get-LocPlaybookPrefEntry -RuleId $RuleId
    if ($pref.AgentIds.Count -gt 0 -and ($pref.AgentIds -notcontains $AgentId)) { return $null }
    $map = Get-LocPlaybookFleetMapping -Rule $rule
    if (-not $map.SupportsFleet) { return $null }
    if (-not (Get-Command Queue-LocFleetCommand -ErrorAction SilentlyContinue)) { return $null }

    # Dedupe pending/running same type
    try {
        $recent = @(Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 20)
        foreach ($c in $recent) {
            if ([string]$c.Type -ne $map.FleetCommand) { continue }
            if ($c.Status -in @('Pending', 'Running')) { return $null }
        }
    }
    catch { Write-Debug $_.Exception.Message }

    $q = Queue-LocFleetCommand -AgentId $AgentId -Type $map.FleetCommand -Payload $map.Payload
    Add-LocEventAudit -Action "AutomationRan" -Detail ("Fleet auto {0} on {1}: {2}" -f $RuleId, $AgentId, $map.FleetCommand) -Operator "system" -Data @{
        RuleId  = $RuleId
        AgentId = $AgentId
        Action  = $map.FleetCommand
        Reason  = $Reason
        Success = [bool]$q.Success
    }
    return $q
}
