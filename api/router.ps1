# api/router.ps1 - Thin /api/v1 router

function Read-LocRequestBody {
    param([System.Net.HttpListenerRequest]$Request)
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    return $reader.ReadToEnd()
}

function Parse-LocJsonBody {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @{} }
    try {
        $obj = $Body | ConvertFrom-Json
        return ConvertTo-Hashtable -InputObject $obj
    }
    catch {
        return $null
    }
}

function Invoke-LocEventIntelRouter {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments
    )

    $request = $Context.Request
    $method = $request.HttpMethod.ToUpperInvariant()
    $resource = if ($Segments.Count -ge 3) { $Segments[2].ToLower() } else { "" }
    $id = if ($Segments.Count -ge 4) { $Segments[3] } else { "" }
    $action = if ($Segments.Count -ge 5) { $Segments[4].ToLower() } else { "" }

    if (-not (Test-LocEventIntelEnabled) -and $resource -ne "event-intel") {
        # Still allow status when disabled
        if ($resource -ne "event-intel") {
            Send-JsonResponse -Context $Context -Success $false -Message "Event Intelligence is disabled" -StatusCode 503
            return
        }
    }

    switch ($resource) {
        "events" {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "GET required" -StatusCode 405
                return
            }
            $max = 200
            if ($request.QueryString["max"]) { [void][int]::TryParse($request.QueryString["max"], [ref]$max) }
            $ring = Get-LocEventRing -Max $max
            if (-not $ring -or $ring.Count -eq 0) { $ring = Get-LocStoredEvents -Max $max }
            Send-JsonResponse -Context $Context -Success $true -Message "Events" -Data @($ring)
            return
        }
        "alerts" {
            if ($method -eq "GET") {
                $alerts = @(Get-LocStoredAlerts)
                $unreadOnly = $request.QueryString["unread"]
                if ($unreadOnly -and ($unreadOnly -eq "1" -or $unreadOnly -match '(?i)true')) {
                    $alerts = @($alerts | Where-Object { -not $_.Acknowledged })
                }
                Send-JsonResponse -Context $Context -Success $true -Message "Alerts" -Data @{
                    Items  = @($alerts | Select-Object -First 100)
                    Unread = @($alerts | Where-Object { -not $_.Acknowledged }).Count
                }
                return
            }
            if ($method -eq "POST" -and $id -and $action -eq "ack") {
                $result = Acknowledge-LocAlert -Id $id
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            Send-JsonResponse -Context $Context -Success $false -Message "Use GET /alerts or POST /alerts/{id}/ack" -StatusCode 400
            return
        }
        "incidents" {
            if ($method -eq "GET" -and -not $id) {
                $statusFilter = $request.QueryString["status"]
                if (-not $statusFilter) { $statusFilter = "active" }
                $sev = $request.QueryString["severity"]
                $list = if ($statusFilter -eq "all") {
                    Get-LocIncidentFiles -Status "all"
                }
                else {
                    Get-LocIncidentFiles -Status $statusFilter
                }
                if ($sev) {
                    $list = @($list | Where-Object { $_.Severity -eq $sev })
                }
                $summary = Get-LocIncidentSummary
                Send-JsonResponse -Context $Context -Success $true -Message "Incidents" -Data @{
                    Summary = $summary
                    Items   = @($list)
                }
                return
            }
            if ($method -eq "GET" -and $id) {
                $inc = Get-LocIncidentById -Id $id
                if (-not $inc) {
                    Send-JsonResponse -Context $Context -Success $false -Message "Not found" -StatusCode 404
                    return
                }
                Send-JsonResponse -Context $Context -Success $true -Message "Incident" -Data $inc
                return
            }
            if ($method -eq "POST" -and $id -and $action -eq "resolve") {
                $note = "Resolved"
                try {
                    $body = Read-LocRequestBody -Request $request
                    $parsed = Parse-LocJsonBody -Body $body
                    if ($parsed -and $parsed.Note) { $note = [string]$parsed.Note }
                }
                catch { }
                $result = Resolve-LocIncident -Id $id -Operator "operator" -Note $note
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -eq "POST" -and $id -and $action -eq "ack") {
                $result = Acknowledge-LocIncident -Id $id
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            Send-JsonResponse -Context $Context -Success $false -Message "Invalid incidents request" -StatusCode 400
            return
        }
        "timeline" {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "GET required" -StatusCode 405
                return
            }
            $max = 100; $hours = 24
            if ($request.QueryString["max"]) { [void][int]::TryParse($request.QueryString["max"], [ref]$max) }
            if ($request.QueryString["hours"]) { [void][int]::TryParse($request.QueryString["hours"], [ref]$hours) }
            Send-JsonResponse -Context $Context -Success $true -Message "Timeline" -Data @(Get-LocGlobalTimeline -Max $max -Hours $hours)
            return
        }
        "rules" {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "GET required" -StatusCode 405
                return
            }
            $rules = @(Get-LocRules | ForEach-Object {
                    [PSCustomObject]@{
                        id             = $_.id
                        eventId        = $_.eventId
                        source         = $_.source
                        threshold      = $_.threshold
                        windowSeconds  = $_.windowSeconds
                        severity       = $_.severity
                        score          = $_.score
                        incident       = $_.incident
                        category       = $_.category
                        notify         = $_.notify
                        automation     = $_.automation
                    }
                })
            Send-JsonResponse -Context $Context -Success $true -Message "Rules" -Data @($rules)
            return
        }
        "notifications" {
            $sub = $id.ToLower()
            if ($sub -eq "prefs") {
                if ($method -eq "GET") {
                    Send-JsonResponse -Context $Context -Success $true -Message "Notification prefs" -Data (Get-LocNotificationPrefs)
                    return
                }
                if ($method -eq "PUT" -or $method -eq "POST") {
                    $body = Read-LocRequestBody -Request $request
                    $parsed = Parse-LocJsonBody -Body $body
                    if ($null -eq $parsed) {
                        Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON" -StatusCode 400
                        return
                    }
                    $ok = Update-LocEventIntelPrefs -Prefs $parsed
                    if ($ok) {
                        Send-JsonResponse -Context $Context -Success $true -Message "Prefs updated" -Data (Get-LocNotificationPrefs)
                    }
                    else {
                        Send-JsonResponse -Context $Context -Success $false -Message "Failed to save prefs" -StatusCode 500
                    }
                    return
                }
            }
            Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/notifications/prefs" -StatusCode 400
            return
        }
        "security-score" {
            Send-JsonResponse -Context $Context -Success $true -Message "Security score" -Data (Get-LocSecurityScorePayload)
            return
        }
        "health-score" {
            Send-JsonResponse -Context $Context -Success $true -Message "Health score" -Data (Get-LocHealthScorePayload)
            return
        }
        "heatmap" {
            Send-JsonResponse -Context $Context -Success $true -Message "Heatmap" -Data (Get-LocAlertHeatmap)
            return
        }
        "event-intel" {
            if ($id.ToLower() -eq "status" -or -not $id) {
                Send-JsonResponse -Context $Context -Success $true -Message "Event Intelligence status" -Data (Get-LocEventIntelStatus)
                return
            }
            Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/event-intel/status" -StatusCode 400
            return
        }
    }

    Send-JsonResponse -Context $Context -Success $false -Message "Unknown Event Intelligence route" -StatusCode 404
}

function Invoke-LocFleetRouter {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments
    )

    $request = $Context.Request
    $method = $request.HttpMethod.ToUpperInvariant()

    if (-not (Test-LocFleetEnabled)) {
        Send-JsonResponse -Context $Context -Success $false -Message "Fleet is disabled" -StatusCode 503
        return
    }

    # segments: api, v1, fleet, ...
    $sub = if ($Segments.Count -ge 4) { $segments[3] } else { "" }
    $subLower = $sub.ToLower()
    $agentSub = if ($Segments.Count -ge 5) { $Segments[4] } else { "" }

    # Agent HMAC routes
    $agentRoutes = @('enroll', 'heartbeat', 'poll', 'results', 'events')
    $needsHmac = ($subLower -in $agentRoutes) -or ($subLower -eq 'scripts' -and $agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'content')

    $body = ""
    $bodyHash = @{}
    if ($method -eq "POST") {
        $body = Read-LocRequestBody -Request $request
        $parsed = Parse-LocJsonBody -Body $body
        if ($null -eq $parsed -and -not [string]::IsNullOrWhiteSpace($body)) {
            Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON body" -StatusCode 400
            return
        }
        if ($parsed) { $bodyHash = $parsed }
    }

    $agentId = $null
    if ($needsHmac) {
        if ($subLower -eq 'enroll') {
            # enroll uses token, not HMAC
        }
        else {
            $auth = Test-LocAgentSignature -Request $request -Body $body
            if (-not $auth.Success) {
                $status = if ($auth.StatusCode) { [int]$auth.StatusCode } else { 401 }
                Send-JsonResponse -Context $Context -Success $false -Message $auth.Message -StatusCode $status
                return
            }
            $agentId = [string]$auth.Data.AgentId
        }
    }

    switch ($subLower) {
        'enroll' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Enroll requires POST" -StatusCode 405
                return
            }
            $token = if ($bodyHash.Token) { [string]$bodyHash.Token } else { "" }
            $computer = if ($bodyHash.ComputerName) { [string]$bodyHash.ComputerName } else { "UNKNOWN" }
            $ver = if ($bodyHash.AgentVersion) { [string]$bodyHash.AgentVersion } else { "2.0.0" }
            $result = Enroll-LocAgent -Token $token -ComputerName $computer -AgentVersion $ver
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        'heartbeat' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Heartbeat requires POST" -StatusCode 405
                return
            }
            $result = Register-LocHeartbeat -AgentId $agentId -Telemetry $bodyHash
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'poll' {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Poll requires GET" -StatusCode 405
                return
            }
            $result = Claim-LocFleetCommands -AgentId $agentId
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'results' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Results requires POST" -StatusCode 405
                return
            }
            $cmdId = if ($bodyHash.CommandId) { [string]$bodyHash.CommandId } else { "" }
            if (-not $cmdId) {
                Send-JsonResponse -Context $Context -Success $false -Message "CommandId required" -StatusCode 400
                return
            }
            $result = Complete-LocFleetCommand -AgentId $agentId -CommandId $cmdId `
                -Success ([bool](if ($null -ne $bodyHash.Success) { $bodyHash.Success } else { $true })) `
                -Message ([string](if ($bodyHash.Message) { $bodyHash.Message } else { "" })) `
                -Data $bodyHash.Data `
                -ExitCode ([int](if ($bodyHash.ExitCode) { $bodyHash.ExitCode } else { 0 })) `
                -DurationMs ([int](if ($bodyHash.DurationMs) { $bodyHash.DurationMs } else { 0 })) `
                -LogLines @($bodyHash.LogLines)
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        'events' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Events requires POST" -StatusCode 405
                return
            }
            $result = Register-LocFleetEvent -AgentId $agentId -Event $bodyHash
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'agents' {
            if ($agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'revoke') {
                if ($method -ne "POST") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Revoke requires POST" -StatusCode 405
                    return
                }
                $result = Revoke-LocAgent -AgentId $agentSub
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($agentSub) {
                if ($method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Agent detail requires GET" -StatusCode 405
                    return
                }
                $result = Get-LocFleetAgentDetail -AgentId $agentSub
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Agents list requires GET" -StatusCode 405
                return
            }
            $result = Get-LocFleetAgents
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'commands' {
            if ($method -eq "POST") {
                $aid = if ($bodyHash.AgentId) { [string]$bodyHash.AgentId } else { "" }
                $type = if ($bodyHash.Type) { [string]$bodyHash.Type } else { "" }
                if (-not $aid -or -not $type) {
                    Send-JsonResponse -Context $Context -Success $false -Message "AgentId and Type required" -StatusCode 400
                    return
                }
                $payload = if ($bodyHash.Payload) { $bodyHash.Payload } else { $null }
                $result = Queue-LocFleetCommand -AgentId $aid -Type $type -Payload $payload
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Commands require GET or POST" -StatusCode 405
                return
            }
            $filterId = $request.QueryString["agentId"]
            $result = Get-LocFleetCommands -AgentId $filterId
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'alerts' {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Alerts require GET" -StatusCode 405
                return
            }
            $result = Get-LocFleetAlerts
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'scripts' {
            if ($agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'content') {
                if ($method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Script content requires GET" -StatusCode 405
                    return
                }
                $result = Get-LocFleetScriptContent -ScriptId $agentSub
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Scripts require GET" -StatusCode 405
                return
            }
            $result = Get-LocFleetScripts
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'enroll-token' {
            if ($Segments.Count -ge 5 -and $Segments[4].ToLower() -eq 'rotate') {
                if ($method -ne "POST") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Rotate requires POST" -StatusCode 405
                    return
                }
                $result = Rotate-LocFleetEnrollToken
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Enroll token requires GET" -StatusCode 405
                return
            }
            $result = Get-LocFleetEnrollToken
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        default {
            Send-JsonResponse -Context $Context -Success $false -Message "Unknown fleet endpoint" -StatusCode 404
        }
    }
}

function Invoke-LocRouter {
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context
    )

    $request = $Context.Request
    $method = $request.HttpMethod.ToUpperInvariant()
    $segments = @($request.Url.AbsolutePath.Trim('/').Split('/') | Where-Object { $_ })

    # Expect api / v1 / ...
    if ($segments.Count -lt 2 -or $segments[0].ToLower() -ne "api" -or $segments[1].ToLower() -ne "v1") {
        Send-JsonResponse -Context $Context -Success $false -Message "API requires /api/v1/ prefix" -StatusCode 400
        return
    }

    $resource = if ($segments.Count -ge 3) { $segments[2].ToLower() } else { "" }

    # Built-in: health
    if ($resource -eq "health") {
        $ver = Get-LocVersion
        $mods = Get-LocModules
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $caption = if ($os) { $os.Caption } else { $env:OS }
        $build = if ($os) { $os.Version } else { "" }

        $data = [PSCustomObject]@{
            Version       = $ver.version
            Name          = $ver.name
            Admin         = Test-IsAdmin
            LoadedModules = $mods.Count
            ModuleErrors  = @(Get-LocModuleErrors)
            PowerShell    = $PSVersionTable.PSVersion.ToString()
            Windows       = ("{0} ({1})" -f $caption, $build).Trim()
            Status        = if ((Get-LocModuleErrors).Count -eq 0) { "Healthy" } else { "Degraded" }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "OK" -Data $data
        return
    }

    # Built-in: modules
    if ($resource -eq "modules") {
        $mods = Get-LocModules | ForEach-Object {
            [PSCustomObject]@{
                id            = $_.Id
                name          = $_.Name
                version       = $_.Version
                icon          = $_.Icon
                description   = $_.Description
                order         = $_.Order
                tier          = $_.Tier
                # Wrap as ArrayList so ConvertTo-Json keeps single-item arrays as JSON arrays
                profiles      = [System.Collections.ArrayList]@($_.Profiles)
                depends       = [System.Collections.ArrayList]@($_.Depends)
                diagnostics   = [System.Collections.ArrayList]@($_.Diagnostics)
                actions       = [System.Collections.ArrayList]@($_.Actions)
                requiresAdmin = [System.Collections.ArrayList]@($_.RequiresAdmin)
                hidden        = $_.Hidden
                capabilities  = [System.Collections.ArrayList]@(if ($_.Capabilities) { $_.Capabilities } else { @() })
            }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Modules loaded" -Data @($mods)
        return
    }

    # Built-in: logs/tail
    if ($resource -eq "logs") {
        $lines = 100
        if ($request.QueryString["lines"]) {
            [void][int]::TryParse($request.QueryString["lines"], [ref]$lines)
        }
        $tail = Get-ConsoleFeed -Lines $lines
        Send-JsonResponse -Context $Context -Success $true -Message "Log tail" -Data @($tail)
        return
    }

    # Built-in: telemetry (lazy refresh on read - never blocks accept loop)
    if ($resource -eq "telemetry") {
        $force = $false
        $forceRaw = $request.QueryString["force"]
        if ($forceRaw -and ($forceRaw -eq "1" -or $forceRaw -match '^(?i)true|yes$')) {
            $force = $true
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Telemetry snapshot" -Data (Get-LocTelemetrySnapshot -Force $force)
        return
    }

    # Built-in: shutdown (stops HttpListener; launcher Wait-Process then exits)
    if ($resource -eq "shutdown") {
        if ($method -ne "POST") {
            Send-JsonResponse -Context $Context -Success $false -Message "Shutdown requires POST" -StatusCode 405
            return
        }
        Write-LocLog -Module "CORE" -Action "Shutdown" -Level "WARN" -Message "Shutdown requested via API"
        Send-JsonResponse -Context $Context -Success $true -Message "Shutting down" -Data @{ Stopping = $true }
        # Response already flushed; stop listener so the accept loop exits.
        if (Get-Command Request-LocShutdown -ErrorAction SilentlyContinue) {
            Request-LocShutdown
        }
        return
    }

    # Built-in: updates/check | updates/apply
    if ($resource -eq "updates") {
        $sub = if ($segments.Count -ge 4) { $segments[3].ToLower() } else { "check" }
        if ($sub -eq "check") {
            $result = Test-LocUpdate
            $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        if ($sub -eq "apply") {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Apply requires POST" -StatusCode 405
                return
            }
            $force = $false
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $body = $reader.ReadToEnd()
                if ($body) {
                    $obj = $body | ConvertFrom-Json
                    if ($obj.Force) { $force = [bool]$obj.Force }
                }
            }
            catch { }
            $result = if ($force) { Apply-LocUpdate -Force } else { Apply-LocUpdate }
            $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/updates/check or /api/v1/updates/apply" -StatusCode 400
        return
    }

    # Built-in: integrity status
    if ($resource -eq "integrity") {
        $sub = if ($segments.Count -ge 4) { $segments[3].ToLower() } else { "status" }
        if ($sub -eq "status") {
            Send-JsonResponse -Context $Context -Success $true -Message "Integrity status" -Data (Get-LocIntegrityStatus)
            return
        }
        Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/integrity/status" -StatusCode 400
        return
    }

    # Built-in: automation status
    if ($resource -eq "automation") {
        $sub = if ($segments.Count -ge 4) { $segments[3].ToLower() } else { "status" }
        if ($sub -eq "status") {
            Send-JsonResponse -Context $Context -Success $true -Message "Automation status" -Data (Get-LocAutomationStatus)
            return
        }
        Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/automation/status" -StatusCode 400
        return
    }

    # Built-in: settings (GET full / POST eventIntel prefs)
    if ($resource -eq "settings") {
        if ($method -eq "GET") {
            $s = Get-LocSettings
            $safe = [PSCustomObject]@{
                port                = $s.port
                cacheTtlSeconds     = $s.cacheTtlSeconds
                taskIntervalSeconds = $s.taskIntervalSeconds
                bindHost            = $s.bindHost
                integrityMode       = if ($s.integrityMode) { $s.integrityMode } else { "warn" }
                eventIntelEnabled   = (Test-LocEventIntelEnabled)
                eventIntel          = (Get-LocEventIntelSettings)
                fleetEnabled        = if ($null -ne $s.fleetEnabled) { [bool]$s.fleetEnabled } else { $true }
            }
            Send-JsonResponse -Context $Context -Success $true -Message "Settings" -Data $safe
            return
        }
        if ($method -eq "POST") {
            $body = Read-LocRequestBody -Request $request
            $parsed = Parse-LocJsonBody -Body $body
            if ($null -eq $parsed) {
                Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON" -StatusCode 400
                return
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
                Send-JsonResponse -Context $Context -Success $true -Message "Settings saved" -Data (Get-LocEventIntelSettings)
            }
            else {
                Send-JsonResponse -Context $Context -Success $false -Message "Failed to save settings" -StatusCode 500
            }
            return
        }
        Send-JsonResponse -Context $Context -Success $false -Message "Use GET or POST /api/v1/settings" -StatusCode 405
        return
    }

    # Built-in: Event Intelligence
    if ($resource -in @("events", "alerts", "incidents", "timeline", "rules", "notifications", "security-score", "health-score", "heatmap", "event-intel")) {
        Invoke-LocEventIntelRouter -Context $Context -Segments $segments
        return
    }

    # Built-in: fleet RMM (before module routes)
    if ($resource -eq "fleet") {
        Invoke-LocFleetRouter -Context $Context -Segments $segments
        return
    }

    # Module route: /api/v1/{module}/{diagnostics|actions}/{name}
    if ($segments.Count -lt 5) {
        Send-JsonResponse -Context $Context -Success $false -Message "Invalid endpoint. Use /api/v1/{module}/{diagnostics|actions}/{name}" -StatusCode 400
        return
    }

    $moduleId = $segments[2]
    $kind = $segments[3].ToLower()
    $actionName = $segments[4]

    if ($kind -ne "diagnostics" -and $kind -ne "actions") {
        Send-JsonResponse -Context $Context -Success $false -Message "Kind must be 'diagnostics' or 'actions'" -StatusCode 400
        return
    }

    $params = @{}
    $forceRefresh = $false

    if ($request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
        $body = $reader.ReadToEnd()
        if ($body) {
            try {
                $obj = $body | ConvertFrom-Json
                foreach ($p in $obj.PSObject.Properties) {
                    $params[$p.Name] = $p.Value
                }
            }
            catch {
                Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON body" -StatusCode 400
                return
            }
        }
    }
    else {
        foreach ($key in $request.QueryString.AllKeys) {
            if ($key) {
                if ($key.ToLower() -eq "refresh" -and $request.QueryString[$key] -in @("1", "true", "yes")) {
                    $forceRefresh = $true
                }
                else {
                    $params[$key] = $request.QueryString[$key]
                }
            }
        }
    }

    if ($kind -eq "actions" -and $request.HttpMethod -ne "POST") {
        Send-JsonResponse -Context $Context -Success $false -Message "Actions require POST" -StatusCode 405
        return
    }

    $result = Invoke-LocModuleAction -ModuleId $moduleId -Kind $kind -ActionName $actionName -Params $params -ForceRefresh $forceRefresh
    $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
    Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
}
