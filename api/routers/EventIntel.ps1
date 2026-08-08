# api/routers/EventIntel.ps1 - Event Intelligence API routes

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
                catch { Write-Debug $_.Exception.Message }
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
