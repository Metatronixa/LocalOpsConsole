# core/AutomationPlaybookRules.ps1 - Playbook rule projection and toggle API

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
