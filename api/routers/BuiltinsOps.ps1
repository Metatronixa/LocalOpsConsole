# api/routers/BuiltinsOps.ps1 - automation, settings, syncme builtins

function Invoke-LocBuiltinAutomation {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments,
        [string]$Method,
        [System.Net.HttpListenerRequest]$Request
    )

    $sub = if ($Segments.Count -ge 4) { $Segments[3].ToLower() } else { "status" }
    $playbookId = if ($Segments.Count -ge 5) { [uri]::UnescapeDataString($Segments[4]) } else { "" }

    if ($sub -eq "status") {
        Send-JsonResponse -Context $Context -Success $true -Message "Automation status" -Data (Get-LocAutomationStatus)
        return $true
    }
    if ($sub -eq "playbooks" -and $Method -eq "POST" -and $playbookId) {
        $body = Read-LocRequestBody -Request $Request
        $parsed = Parse-LocJsonBody -Body $body
        if ($null -eq $parsed) { $parsed = @{} }

        $runNow = $false
        if ($Segments.Count -ge 6 -and $Segments[5].ToLower() -eq "run") { $runNow = $true }

        if ($runNow) {
            $overrideIds = $null
            if ($parsed -is [hashtable]) {
                if ($parsed.ContainsKey("agentIds")) { $overrideIds = @($parsed["agentIds"]) }
                elseif ($parsed.ContainsKey("AgentIds")) { $overrideIds = @($parsed["AgentIds"]) }
            }
            elseif ($parsed.PSObject.Properties['agentIds']) { $overrideIds = @($parsed.agentIds) }
            elseif ($parsed.PSObject.Properties['AgentIds']) { $overrideIds = @($parsed.AgentIds) }
            $result = Invoke-LocPlaybookRunNow -RuleId $playbookId -AgentIds $overrideIds -Operator "operator"
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return $true
        }

        if ($parsed -isnot [hashtable] -and -not ($parsed.PSObject.Properties.Name -contains 'enabled' -or $parsed.PSObject.Properties.Name -contains 'Enabled')) {
            # keep hashtable path below
        }
        $enabledRaw = $null
        if ($parsed -is [hashtable]) {
            if ($parsed.ContainsKey("enabled")) { $enabledRaw = $parsed["enabled"] }
            elseif ($parsed.ContainsKey("Enabled")) { $enabledRaw = $parsed["Enabled"] }
        }
        else {
            if ($parsed.PSObject.Properties['enabled']) { $enabledRaw = $parsed.enabled }
            elseif ($parsed.PSObject.Properties['Enabled']) { $enabledRaw = $parsed.Enabled }
        }
        if ($null -eq $enabledRaw) {
            Send-JsonResponse -Context $Context -Success $false -Message "enabled (true|false) required" -StatusCode 400
            return $true
        }
        $enabledBool = $false
        if ($enabledRaw -is [bool]) { $enabledBool = $enabledRaw }
        elseif ("$enabledRaw" -match '^(?i)(true|1|yes)$') { $enabledBool = $true }
        elseif ("$enabledRaw" -match '^(?i)(false|0|no)$') { $enabledBool = $false }
        else {
            Send-JsonResponse -Context $Context -Success $false -Message "enabled must be true or false" -StatusCode 400
            return $true
        }
        $scopeVal = $null
        $agentIdsVal = $null
        if ($parsed -is [hashtable]) {
            if ($parsed.ContainsKey("scope")) { $scopeVal = [string]$parsed["scope"] }
            elseif ($parsed.ContainsKey("Scope")) { $scopeVal = [string]$parsed["Scope"] }
            if ($parsed.ContainsKey("agentIds")) { $agentIdsVal = @($parsed["agentIds"]) }
            elseif ($parsed.ContainsKey("AgentIds")) { $agentIdsVal = @($parsed["AgentIds"]) }
        }
        else {
            if ($parsed.PSObject.Properties['scope']) { $scopeVal = [string]$parsed.scope }
            elseif ($parsed.PSObject.Properties['Scope']) { $scopeVal = [string]$parsed.Scope }
            if ($parsed.PSObject.Properties['agentIds']) { $agentIdsVal = @($parsed.agentIds) }
            elseif ($parsed.PSObject.Properties['AgentIds']) { $agentIdsVal = @($parsed.AgentIds) }
        }
        $result = Set-LocPlaybookEnabled -RuleId $playbookId -Enabled $enabledBool -Scope $scopeVal -AgentIds $agentIdsVal -Operator "operator"
        $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
        Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
        return $true
    }
    Send-JsonResponse -Context $Context -Success $false -Message "Use GET /api/v1/automation/status, POST /api/v1/automation/playbooks/{ruleId}, or POST .../playbooks/{ruleId}/run" -StatusCode 400
    return $true
}

function Invoke-LocBuiltinSettings {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments,
        [string]$Method,
        [System.Net.HttpListenerRequest]$Request
    )

    $settingsSub = if ($Segments.Count -ge 4) { $Segments[3].ToLower() } else { "" }

    if ($Method -eq "POST" -and $settingsSub -eq "test-channel") {
        $body = Read-LocRequestBody -Request $Request
        $parsed = Parse-LocJsonBody -Body $body
        if ($null -eq $parsed) {
            Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON" -StatusCode 400
            return $true
        }
        $channel = $null
        if ($parsed.ContainsKey("channel")) { $channel = [string]$parsed["channel"] }
        elseif ($parsed.ContainsKey("Channel")) { $channel = [string]$parsed["Channel"] }
        if ([string]::IsNullOrWhiteSpace($channel)) {
            Send-JsonResponse -Context $Context -Success $false -Message "channel required" -StatusCode 400
            return $true
        }
        $result = Test-LocNotifyChannel -Channel $channel
        $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
        Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
        return $true
    }

    if ($Method -eq "GET") {
        $s = Get-LocSettings
        $safe = [PSCustomObject]@{
            port                = $s.port
            cacheTtlSeconds     = $s.cacheTtlSeconds
            taskIntervalSeconds = $s.taskIntervalSeconds
            bindHost            = $s.bindHost
            integrityMode       = if ($s.integrityMode) { $s.integrityMode } else { "warn" }
            productMode         = if (Get-Command Get-LocProductMode -ErrorAction SilentlyContinue) { Get-LocProductMode } else { "desktop" }
            license             = if (Get-Command Get-LocLicenseSummary -ErrorAction SilentlyContinue) { Get-LocLicenseSummary } else { $null }
            eventIntelEnabled   = (Test-LocEventIntelEnabled)
            eventIntel          = (Get-LocEventIntelSettingsForApi)
            fleetEnabled        = if ($null -ne $s.fleetEnabled) { [bool]$s.fleetEnabled } else { $true }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Settings" -Data $safe
        return $true
    }
    if ($Method -eq "POST") {
        $body = Read-LocRequestBody -Request $Request
        $parsed = Parse-LocJsonBody -Body $body
        if ($null -eq $parsed) {
            Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON" -StatusCode 400
            return $true
        }
        $prefs = @{}
        if ($parsed.ContainsKey("eventIntel")) {
            $ei = $parsed["eventIntel"]
            if ($ei -is [hashtable]) { $prefs = $ei }
            else {
                foreach ($p in $ei.PSObject.Properties) { $prefs[$p.Name] = $p.Value }
            }
        }
        else {
            $prefs = $parsed
        }
        $ok = Update-LocEventIntelPrefs -Prefs $prefs
        if ($ok) {
            Send-JsonResponse -Context $Context -Success $true -Message "Settings saved" -Data (Get-LocEventIntelSettingsForApi)
        }
        else {
            Send-JsonResponse -Context $Context -Success $false -Message "Failed to save settings" -StatusCode 500
        }
        return $true
    }
    Send-JsonResponse -Context $Context -Success $false -Message "Use GET or POST /api/v1/settings (or POST /api/v1/settings/test-channel)" -StatusCode 405
    return $true
}

function Invoke-LocBuiltinSyncMe {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments,
        [string]$Method,
        [System.Net.HttpListenerRequest]$Request
    )

    $syncSub = if ($Segments.Count -ge 4) { $Segments[3].ToLower() } else { "" }
    if ($syncSub -in @("register", "heartbeat")) {
        if ($Method -ne "POST") {
            Send-JsonResponse -Context $Context -Success $false -Message "POST required" -StatusCode 405
            return $true
        }
        # Load helpers before loopback check (Test-LocRequestIsLoopback lives here)
        if (-not (Get-Command Save-LocSyncMeRegistration -ErrorAction SilentlyContinue)) {
            $regLib = Join-Path (Get-LocRoot) "modules\SyncMe\lib\SyncMeRegister.ps1"
            if (Test-Path -LiteralPath $regLib) { . $regLib }
        }
        if (-not (Get-Command Save-LocSyncMeRegistration -ErrorAction SilentlyContinue)) {
            Send-JsonResponse -Context $Context -Success $false -Message "SyncMe register helpers not loaded" -StatusCode 500
            return $true
        }
        if (-not (Test-LocRequestIsLoopback -Request $Request)) {
            Send-JsonResponse -Context $Context -Success $false -Message "SyncMe register is loopback-only in this release" -StatusCode 403
            return $true
        }
        $body = Read-LocRequestBody -Request $Request
        $parsed = Parse-LocJsonBody -Body $body
        if ($null -eq $parsed) {
            Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON" -StatusCode 400
            return $true
        }
        $result = Save-LocSyncMeRegistration -Fields $parsed
        $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
        Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
        return $true
    }
    # Fall through to module diagnostics/actions (GetStatus, OpenConsole, …)
    return $false
}
