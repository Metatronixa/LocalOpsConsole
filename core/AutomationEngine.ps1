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
    "clear-print-queue" = {
        param($Context)
        try {
            $removed = 0
            $printers = @(Get-Printer -ErrorAction SilentlyContinue)
            foreach ($p in $printers) {
                $jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue)
                foreach ($j in $jobs) {
                    try {
                        Remove-PrintJob -PrinterName $j.PrinterName -ID $j.Id -ErrorAction Stop
                        $removed++
                    }
                    catch { }
                }
            }
            return @{ Success = $true; Message = "Cleared $removed print job(s) across $($printers.Count) printer(s)" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "network-soft-repair" = {
        param($Context)
        try {
            $steps = @()
            try {
                Clear-DnsClientCache -ErrorAction Stop
                $steps += "Clear-DnsClientCache"
            }
            catch {
                $null = ipconfig /flushdns 2>&1
                $steps += "ipconfig /flushdns"
            }
            $null = ipconfig /flushdns 2>&1
            if ($steps -notcontains "ipconfig /flushdns") { $steps += "ipconfig /flushdns" }
            $null = ipconfig /release 2>&1
            $steps += "ipconfig /release"
            Start-Sleep -Seconds 1
            $null = ipconfig /renew 2>&1
            $steps += "ipconfig /renew"
            return @{ Success = $true; Message = ("Network soft repair: {0}" -f ($steps -join " → ")) }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "restart-update-stack" = {
        param($Context)
        $names = @("wuauserv", "bits")
        $ok = @()
        $fail = @()
        foreach ($svcName in $names) {
            try {
                Restart-Service -Name $svcName -Force -ErrorAction Stop
                Start-Sleep -Seconds 1
                $svc = Get-Service -Name $svcName -ErrorAction Stop
                if ($svc.Status -eq "Running") {
                    $ok += $svcName
                }
                else {
                    $fail += "$svcName=$($svc.Status)"
                }
            }
            catch {
                $fail += "$svcName=$($_.Exception.Message)"
            }
        }
        if ($fail.Count -eq 0) {
            return @{ Success = $true; Message = ("Restarted update stack: {0}" -f ($ok -join ", ")) }
        }
        if ($ok.Count -gt 0) {
            return @{ Success = $false; Message = ("Partial update stack restart. OK: {0}; Failed: {1}" -f ($ok -join ", "), ($fail -join "; ")) }
        }
        return @{ Success = $false; Message = ("Update stack restart failed: {0}" -f ($fail -join "; ")) }
    }
    "capture-process-snapshot" = {
        param($Context)
        try {
            $procs = @(Get-Process -ErrorAction SilentlyContinue |
                Sort-Object -Property @{ Expression = 'CPU'; Descending = $true }, @{ Expression = 'WorkingSet64'; Descending = $true } |
                Select-Object -First 15)
            if ($procs.Count -eq 0) {
                return @{ Success = $true; Message = "No processes available for snapshot" }
            }
            $lines = foreach ($p in $procs) {
                $mb = [math]::Round(($p.WorkingSet64 / 1MB), 1)
                $cpu = if ($null -eq $p.CPU) { 0 } else { [math]::Round([double]$p.CPU, 1) }
                "{0}(pid={1},cpu={2}s,ws={3}MB)" -f $p.ProcessName, $p.Id, $cpu, $mb
            }
            return @{ Success = $true; Message = ("Top processes: {0}" -f ($lines -join "; ")) }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
}

function Get-LocPlaybookPrefsPath {
    return (Join-Path (Get-LocRoot) "data\automation\playbook-prefs.json")
}

function Get-LocPlaybookPrefs {
    $path = Get-LocPlaybookPrefsPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{}
    }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{} }
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { return [PSCustomObject]@{} }
        return $obj
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "PlaybookPrefs" -Level "WARN" -Message $_.Exception.Message
        return [PSCustomObject]@{}
    }
}

function Save-LocPlaybookPrefs {
    param([object]$Prefs)
    $path = Get-LocPlaybookPrefsPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    try {
        $json = ($Prefs | ConvertTo-Json -Depth 8 -Compress:$false)
        $tmp = "$path.tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path $path) { Remove-Item $path -Force }
        Move-Item $tmp $path -Force
        return $true
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "PlaybookPrefs" -Level "ERROR" -Message $_.Exception.Message
        return $false
    }
}

function Get-LocPlaybookPrefEntry {
    param([string]$RuleId)
    $id = [string]$RuleId
    $prefs = Get-LocPlaybookPrefs
    $enabled = $false
    $scope = "local"
    $agentIds = @()
    $hasPref = $false
    if ($prefs -and $prefs.PSObject.Properties[$id]) {
        $hasPref = $true
        $entry = $prefs.$id
        if ($entry -is [bool]) {
            $enabled = [bool]$entry
        }
        elseif ($entry -is [hashtable]) {
            if ($entry.ContainsKey('enabled')) { $enabled = [bool]$entry['enabled'] }
            if ($entry.ContainsKey('scope') -and $entry['scope']) { $scope = [string]$entry['scope'] }
            if ($entry.ContainsKey('agentIds')) { $agentIds = @($entry['agentIds'] | ForEach-Object { [string]$_ }) }
        }
        elseif ($entry) {
            if ($entry.PSObject.Properties['enabled']) { $enabled = [bool]$entry.enabled }
            if ($entry.PSObject.Properties['scope'] -and $entry.scope) { $scope = [string]$entry.scope }
            if ($entry.PSObject.Properties['agentIds']) { $agentIds = @($entry.agentIds | ForEach-Object { [string]$_ }) }
        }
    }
    $scope = $scope.ToLowerInvariant()
    if ($scope -notin @('local', 'fleet', 'both')) { $scope = 'local' }
    return [PSCustomObject]@{
        RuleId   = $id
        HasPref  = $hasPref
        Enabled  = $enabled
        Scope    = $scope
        AgentIds = @($agentIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}

function Test-LocAutomationEnabledForRule {
    param([object]$Rule)
    if (-not $Rule -or -not $Rule.automation) { return $false }
    $ruleId = [string]$Rule.id
    if ([string]::IsNullOrWhiteSpace($ruleId)) { return $false }

    $pref = Get-LocPlaybookPrefEntry -RuleId $ruleId
    if ($pref.HasPref) { return [bool]$pref.Enabled }
    return [bool]$Rule.automation.enabled
}

function Test-LocPlaybookScopeIncludesLocal {
    param([string]$Scope)
    $s = ([string]$Scope).ToLowerInvariant()
    return ($s -eq 'local' -or $s -eq 'both')
}

function Test-LocPlaybookScopeIncludesFleet {
    param([string]$Scope)
    $s = ([string]$Scope).ToLowerInvariant()
    return ($s -eq 'fleet' -or $s -eq 'both')
}

function Get-LocPlaybookFleetMapping {
    param([object]$Rule)
    if (-not $Rule -or -not $Rule.automation) {
        return [PSCustomObject]@{ SupportsFleet = $false; FleetCommand = $null; Payload = @{} }
    }
    $action = [string]$Rule.automation.action
    $svc = if ($Rule.automation.service) { [string]$Rule.automation.service } else { "" }
    $type = $null
    $payload = @{}
    switch ($action) {
        "restart-service" {
            if ($svc -eq "Spooler" -or ([string]$Rule.id -match 'spooler')) {
                $type = "RestartSpooler"
            }
            elseif ($svc) {
                $type = "RestartService"
                $payload = @{ ServiceName = $svc }
            }
            else {
                $type = "RestartService"
            }
        }
        "disk-cleanup" { $type = "DiskCleanup" }
        "clear-print-queue" { $type = "ClearPrintQueue" }
        "network-soft-repair" { $type = "NetworkSoftRepair" }
        "restart-update-stack" { $type = "RestartUpdateStack" }
        "capture-process-snapshot" { $type = "CaptureProcessSnapshot" }
        "notify-only" { $type = $null }
        "verify-service" { $type = $null }
        default { $type = $null }
    }
    return [PSCustomObject]@{
        SupportsFleet = -not [string]::IsNullOrWhiteSpace($type)
        FleetCommand  = $type
        Payload       = $payload
        Action        = $action
    }
}

function Resolve-LocPlaybookFleetAgentIds {
    param(
        [string[]]$AgentIds = @(),
        [string[]]$OverrideAgentIds = $null
    )
    $filter = if ($null -ne $OverrideAgentIds) { @($OverrideAgentIds) } else { @($AgentIds) }
    $filter = @($filter | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })

    $online = @()
    if (Get-Command Get-LocFleetAgents -ErrorAction SilentlyContinue) {
        $res = Get-LocFleetAgents
        if ($res -and $res.Success) {
            foreach ($a in @($res.Data)) {
                if ($a.Online -and -not $a.Revoked) {
                    $online += [string]$a.Id
                }
            }
        }
    }
    if ($filter.Count -eq 0) { return @($online) }
    return @($online | Where-Object { $filter -contains $_ })
}

function New-LocPlaybookRuleProjection {
    param(
        [object]$Rule,
        [bool]$Enabled,
        [string]$Scope = "local",
        [string[]]$AgentIds = @()
    )
    $auto = $Rule.automation
    $title = if ($Rule.incident) { [string]$Rule.incident } elseif ($Rule.title) { [string]$Rule.title } else { [string]$Rule.id }
    $risk = if ($auto.risk) { [string]$auto.risk } else { "" }
    $map = Get-LocPlaybookFleetMapping -Rule $Rule
    return [PSCustomObject]@{
        RuleId         = $Rule.id
        Title          = $title
        Category       = $Rule.category
        Enabled        = $Enabled
        DefaultEnabled = [bool]$auto.enabled
        Action         = [string]$auto.action
        Service        = if ($auto.service) { [string]$auto.service } else { $null }
        CloseOnSuccess = [bool]$auto.closeOnSuccess
        Description    = if ($auto.description) { [string]$auto.description } else { "" }
        Risk           = $risk
        Scope          = $Scope
        AgentIds       = @($AgentIds)
        SupportsFleet  = [bool]$map.SupportsFleet
        FleetCommand   = $map.FleetCommand
    }
}

function Set-LocPlaybookEnabled {
    param(
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][bool]$Enabled,
        [string]$Scope = $null,
        [string[]]$AgentIds = $null,
        [string]$Operator = "operator"
    )
    $id = $RuleId.Trim()
    if ([string]::IsNullOrWhiteSpace($id)) {
        return New-ApiResult -Success $false -Message "RuleId required" -StatusCode 400
    }

    $rule = $null
    if (Get-Command Get-LocRules -ErrorAction SilentlyContinue) {
        $rule = @(Get-LocRules) | Where-Object { $_.id -eq $id } | Select-Object -First 1
    }
    if (-not $rule) {
        return New-ApiResult -Success $false -Message "Rule not found: $id" -StatusCode 404
    }
    if (-not $rule.automation) {
        return New-ApiResult -Success $false -Message "Rule has no automation playbook: $id" -StatusCode 400
    }

    $prev = Get-LocPlaybookPrefEntry -RuleId $id
    $scopeVal = if (-not [string]::IsNullOrWhiteSpace($Scope)) { $Scope.Trim().ToLowerInvariant() } else { $prev.Scope }
    if ($scopeVal -notin @('local', 'fleet', 'both')) { $scopeVal = 'local' }
    $idsVal = if ($null -ne $AgentIds) {
        @($AgentIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    } else {
        @($prev.AgentIds)
    }

    $prefs = Get-LocPlaybookPrefs
    if (-not $prefs) { $prefs = [PSCustomObject]@{} }
    $entry = [PSCustomObject]@{
        enabled   = $Enabled
        scope     = $scopeVal
        agentIds  = @($idsVal)
        updatedAt = (Get-Date).ToUniversalTime().ToString("o")
        updatedBy = $Operator
    }
    $prefs | Add-Member -NotePropertyName $id -NotePropertyValue $entry -Force
    if (-not (Save-LocPlaybookPrefs -Prefs $prefs)) {
        return New-ApiResult -Success $false -Message "Failed to save playbook prefs" -StatusCode 500
    }

    Add-LocEventAudit -Action "PlaybookToggled" -Detail ("Playbook {0} -> {1} scope={2}" -f $id, $Enabled, $scopeVal) -Operator $Operator -Data @{
        RuleId   = $id
        Enabled  = $Enabled
        Scope    = $scopeVal
        AgentIds = @($idsVal)
    }

    $item = New-LocPlaybookRuleProjection -Rule $rule -Enabled $Enabled -Scope $scopeVal -AgentIds $idsVal
    return New-ApiResult -Success $true -Message ($(if ($Enabled) { "Playbook enabled" } else { "Playbook disabled" })) -Data $item
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
        $pref = Get-LocPlaybookPrefEntry -RuleId $r.id
        $effective = if ($pref.HasPref) { [bool]$pref.Enabled } else { [bool]$auto.enabled }
        $scope = if ($pref.HasPref) { $pref.Scope } else { "local" }
        $agentIds = if ($pref.HasPref) { @($pref.AgentIds) } else { @() }
        $items += (New-LocPlaybookRuleProjection -Rule $r -Enabled $effective -Scope $scope -AgentIds $agentIds)
    }
    return $items
}

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
    catch { }

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
