# core/AutomationEngine.ps1 - Opt-in remediations with audit trail

$script:LocAutomationHandlers = @{
    "restart-service" = {
        param($Context)
        $svcName = $null
        if ($Context.Event -and $Context.Event.Data) {
            if ($Context.Event.Data -is [hashtable] -and $Context.Event.Data.ContainsKey("service")) {
                $svcName = [string]$Context.Event.Data["service"]
            }
            elseif ($Context.Event.Data.service) { $svcName = [string]$Context.Event.Data.service }
        }
        if (-not $svcName -and $Context.Rule -and $Context.Rule.automation -and $Context.Rule.automation.service) {
            $svcName = [string]$Context.Rule.automation.service
        }
        if (-not $svcName) { return @{ Success = $false; Message = "No service specified" } }
        try {
            Restart-Service -Name $svcName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne "Running") {
                return @{ Success = $false; Message = "Restarted $svcName but status is $($svc.Status)" }
            }
            return @{ Success = $true; Message = "Restarted and verified $svcName is Running" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "verify-service" = {
        param($Context)
        $svcName = $null
        if ($Context.Rule -and $Context.Rule.automation -and $Context.Rule.automation.service) {
            $svcName = [string]$Context.Rule.automation.service
        }
        if (-not $svcName) { return @{ Success = $false; Message = "No service specified" } }
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            $ok = ($svc.Status -eq "Running")
            return @{ Success = $ok; Message = "$svcName is $($svc.Status)" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "disk-cleanup" = {
        param($Context)
        try {
            $temp = $env:TEMP
            $removed = 0
            Get-ChildItem -Path $temp -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
                Select-Object -First 200 |
                ForEach-Object {
                    try { Remove-Item $_.FullName -Force -ErrorAction Stop; $removed++ } catch { }
                }
            return @{ Success = $true; Message = "Removed $removed old temp file(s)" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "notify-only" = {
        param($Context)
        return @{ Success = $true; Message = "Notification-only playbook acknowledged" }
    }
}

function Get-LocAutomationRules {
    $rules = @()
    if (Get-Command Get-LocRules -ErrorAction SilentlyContinue) {
        $rules = @(Get-LocRules)
    }
    $items = @()
    foreach ($r in $rules) {
        $auto = $r.automation
        if (-not $auto) { continue }
        $items += [PSCustomObject]@{
            RuleId        = $r.id
            Title         = $r.title
            Category      = $r.category
            Enabled       = [bool]$auto.enabled
            Action        = [string]$auto.action
            Service       = if ($auto.service) { [string]$auto.service } else { $null }
            CloseOnSuccess = [bool]$auto.closeOnSuccess
            Description   = if ($auto.description) { [string]$auto.description } else { "" }
        }
    }
    return $items
}

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
                    if ($obj.Action -match '^Automation') {
                        $items += $obj
                    }
                }
                catch { }
            }
        }
    }
    catch { }
    return @($items | Select-Object -Last $Max)
}

function Invoke-LocAutomationForRule {
    param(
        [object]$Rule,
        [object]$Incident,
        [object]$Event
    )

    if (-not $Rule -or -not $Rule.automation) { return }
    $auto = $Rule.automation
    if (-not $auto.enabled) { return }

    $action = [string]$auto.action
    if ([string]::IsNullOrWhiteSpace($action)) { return }

    if (-not $script:LocAutomationHandlers.ContainsKey($action)) {
        Add-LocEventAudit -Action "AutomationSkipped" -Detail "Unknown action $action" -Data @{ RuleId = $Rule.id; IncidentId = $Incident.Id }
        return
    }

    $context = @{
        Rule     = $Rule
        Incident = $Incident
        Event    = $Event
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

    # Optional verify step
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
        Note          = 'Automation is opt-in per rule (automation.enabled). Enable carefully; actions are audited.'
    }
}
