# core/NotificationManager.ps1 - Channel send, incident notify, prefs, test

function Invoke-LocChannelSend {
    param(
        [string]$Channel,
        [object]$Alert,
        [object]$Incident
    )
    $ei = Get-LocEventIntelSettings
    $cfg = $null
    if ($ei.channelConfig -and $ei.channelConfig.PSObject.Properties[$Channel]) {
        $cfg = $ei.channelConfig.$Channel
    }

    switch ($Channel.ToLower()) {
        "desktop" {
            if (Get-Command Send-LocNotifyDesktop -ErrorAction SilentlyContinue) {
                return Send-LocNotifyDesktop -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "email" {
            if (Get-Command Send-LocNotifyEmail -ErrorAction SilentlyContinue) {
                return Send-LocNotifyEmail -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "teams" {
            if (Get-Command Send-LocNotifyTeams -ErrorAction SilentlyContinue) {
                return Send-LocNotifyTeams -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "slack" {
            if (Get-Command Send-LocNotifySlack -ErrorAction SilentlyContinue) {
                return Send-LocNotifySlack -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "discord" {
            if (Get-Command Send-LocNotifyDiscord -ErrorAction SilentlyContinue) {
                return Send-LocNotifyDiscord -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "webhook" {
            if (Get-Command Send-LocNotifyWebhook -ErrorAction SilentlyContinue) {
                return Send-LocNotifyWebhook -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "syslog" {
            if (Get-Command Send-LocNotifySyslog -ErrorAction SilentlyContinue) {
                return Send-LocNotifySyslog -Alert $Alert -Incident $Incident -Config $cfg
            }
        }
        "snmp" {
            Write-LocLog -Module "EVENTINTEL" -Action "Notify" -Level "INFO" -Message "SNMP trap not implemented"
            return @{ Success = $false; Message = "SNMP not implemented" }
        }
    }
    return @{ Success = $false; Message = "channel handler missing" }
}

function Invoke-LocIncidentNotify {
    param(
        [Parameter(Mandatory)][object]$Incident,
        [object]$Rule = $null,
        [bool]$IsNew = $true
    )

    Import-LocNotificationChannels

    if ($Rule -and $Rule.notify -eq $false) { return }

    if (-not (Test-LocNotifyLevelAllowed -Severity $Incident.Severity -Category $Incident.Category)) {
        return
    }

    $window = 3600
    if ($Rule -and $null -ne $Rule.suppressSeconds) { $window = [int]$Rule.suppressSeconds }

    $key = Get-LocSuppressionKey -Incident $Incident -Rule $Rule
    $existing = Test-LocSuppressed -Key $key -WindowSeconds $window
    $supp = Update-LocSuppression -Key $key -Title $Incident.Title -WindowSeconds $window

    $repeat = if ($supp) { [int]$supp.Count } else { 1 }
    $suppressedRepeat = ($null -ne $existing -and -not $IsNew -and $repeat -gt 1)

    $msg = $Incident.Title
    if ($suppressedRepeat) {
        $msg = "{0} - repeated {1} times past hour" -f $Incident.Title, $repeat
        # Only notify every 5th repeat after first to reduce storms
        if (($repeat % 5) -ne 0) {
            $alertQuiet = New-LocAlertRecord -Incident $Incident -Message $msg -RepeatCount $repeat -Suppressed $true
            $eiDash = Get-LocEventIntelSettings
            if ($eiDash.channels -and $eiDash.channels.dashboard) {
                Add-LocAlert -Alert $alertQuiet
            }
            Add-LocTimelineEntry -Incident $Incident -Type "suppression" -Title "Suppressed repeat" -Detail $msg -Severity $Incident.Severity | Out-Null
            Write-LocIncidentFile -Incident $Incident -StatusFolder "active"
            return
        }
    }

    $windowOk = Test-LocNotifyWindowAllowed
    $alert = New-LocAlertRecord -Incident $Incident -Message $msg -RepeatCount $repeat -Suppressed (-not $windowOk.Allowed)

    $ei = Get-LocEventIntelSettings
    if ($ei.channels -and $ei.channels.dashboard) {
        Add-LocAlert -Alert $alert
    }

    Add-LocTimelineEntry -Incident $Incident -Type "notification" -Title "Notification" -Detail $msg -Severity $Incident.Severity `
        -Data @{ Channels = @(); Window = $windowOk.Reason } | Out-Null
    Write-LocIncidentFile -Incident $Incident -StatusFolder "active"

    if (-not $windowOk.Allowed) {
        Add-LocEventAudit -Action "NotifyDeferred" -Detail $windowOk.Reason -Data @{ IncidentId = $Incident.Id }
        return
    }

    $channels = $ei.channels
    if (-not $channels) { return }

    foreach ($prop in $channels.PSObject.Properties) {
        $name = $prop.Name
        if ($name -eq "dashboard") { continue }
        if (-not [bool]$prop.Value) { continue }
        try {
            Invoke-LocChannelSend -Channel $name -Alert $alert -Incident $Incident
        }
        catch {
            Write-LocLog -Module "EVENTINTEL" -Action "Notify" -Level "WARN" -Message "$name failed: $($_.Exception.Message)"
        }
    }

    Add-LocEventAudit -Action "NotifySent" -Detail $msg -Data @{ IncidentId = $Incident.Id; AlertId = $alert.Id }
}

function Get-LocNotificationPrefs {
    $ei = Get-LocEventIntelSettingsForApi
    return [PSCustomObject]@{
        notifyLevel       = $ei.notifyLevel
        notifyCategories  = @($ei.notifyCategories)
        quietHours        = $ei.quietHours
        maintenanceWindow = $ei.maintenanceWindow
        businessHours     = $ei.businessHours
        channels          = $ei.channels
        channelConfig     = $ei.channelConfig
        snmp              = [PSCustomObject]@{ implemented = $false; note = "SNMP Trap deferred" }
    }
}

function Test-LocNotifyChannel {
    param(
        [Parameter(Mandatory)][string]$Channel
    )
    Import-LocNotificationChannels
    $name = $Channel.Trim().ToLower()
    $allowed = @('desktop', 'dashboard', 'email', 'teams', 'slack', 'discord', 'webhook', 'syslog')
    if ($allowed -notcontains $name) {
        return New-ApiResult -Success $false -Message "Unknown channel: $Channel" -StatusCode 400
    }

    $incident = [PSCustomObject]@{
        Id       = "test-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Title    = "LocalOpsConsole test ($name)"
        Message  = "Test notification from Settings"
        Severity = "Info"
        Category = "Test"
        Score    = 0
    }
    $alert = New-LocAlertRecord -Incident $incident -Message "This is a test notification for the $name channel."

    if ($name -eq 'dashboard') {
        Add-LocAlert -Alert $alert
        return New-ApiResult -Success $true -Message "Test alert added to dashboard inbox" -Data @{ Channel = $name; AlertId = $alert.Id }
    }

    try {
        $result = Invoke-LocChannelSend -Channel $name -Alert $alert -Incident $incident
        if ($null -eq $result) {
            return New-ApiResult -Success $false -Message "Channel handler returned nothing (is it configured?)" -StatusCode 400
        }
        if ($result -is [hashtable]) {
            $ok = [bool]$result.Success
            $msg = if ($result.Message) { [string]$result.Message } else { if ($ok) { "sent" } else { "failed" } }
            return New-ApiResult -Success $ok -Message $msg -Data @{ Channel = $name } -StatusCode $(if ($ok) { 200 } else { 400 })
        }
        return New-ApiResult -Success $true -Message "Test sent" -Data @{ Channel = $name }
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}
