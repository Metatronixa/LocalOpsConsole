# core/AutomationPlaybookPrefs.ps1 - Playbook preference storage and fleet mapping

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
