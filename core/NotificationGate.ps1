# core/NotificationGate.ps1 - Channel load, quiet hours, suppression, alert records

$script:LocNotifyChannelsLoaded = $false

function Import-LocNotificationChannels {
    if ($script:LocNotifyChannelsLoaded) { return }
    $dir = Join-Path (Get-LocRoot) "notifications"
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter "*.ps1" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { . $_.FullName } catch {
                Write-LocLog -Module "EVENTINTEL" -Action "NotifyLoad" -Level "WARN" -Message $_.Exception.Message
            }
        }
    }
    $script:LocNotifyChannelsLoaded = $true
}

function Test-LocTimeInRange {
    param([string]$Start, [string]$End, [datetime]$Now = (Get-Date))
    if ([string]::IsNullOrWhiteSpace($Start) -or [string]::IsNullOrWhiteSpace($End)) { return $false }
    try {
        $startTs = [datetime]::ParseExact($Start, "HH:mm", $null)
        $endTs = [datetime]::ParseExact($End, "HH:mm", $null)
        $t = $Now.TimeOfDay
        $s = $startTs.TimeOfDay
        $e = $endTs.TimeOfDay
        if ($s -le $e) {
            return ($t -ge $s -and $t -le $e)
        }
        # overnight
        return ($t -ge $s -or $t -le $e)
    }
    catch { return $false }
}

function Test-LocNotifyWindowAllowed {
    $ei = Get-LocEventIntelSettings
    $now = Get-Date

    if ($ei.maintenanceWindow -and $ei.maintenanceWindow.enabled) {
        if (Test-LocTimeInRange -Start ([string]$ei.maintenanceWindow.start) -End ([string]$ei.maintenanceWindow.end) -Now $now) {
            return @{ Allowed = $false; Reason = "maintenance" }
        }
    }

    if ($ei.quietHours -and $ei.quietHours.enabled) {
        if (Test-LocTimeInRange -Start ([string]$ei.quietHours.start) -End ([string]$ei.quietHours.end) -Now $now) {
            return @{ Allowed = $false; Reason = "quietHours" }
        }
    }

    if ($ei.businessHours -and $ei.businessHours.enabled) {
        $days = @($ei.businessHours.days)
        $dow = [int]$now.DayOfWeek
        if ($days.Count -gt 0 -and $days -notcontains $dow) {
            return @{ Allowed = $false; Reason = "businessHours" }
        }
        if (-not (Test-LocTimeInRange -Start ([string]$ei.businessHours.start) -End ([string]$ei.businessHours.end) -Now $now)) {
            return @{ Allowed = $false; Reason = "businessHours" }
        }
    }

    return @{ Allowed = $true; Reason = "" }
}

function Test-LocNotifyLevelAllowed {
    param([string]$Severity, [string]$Category)
    $ei = Get-LocEventIntelSettings
    $level = [string]$ei.notifyLevel
    $sev = [string]$Severity

    switch -Regex ($level) {
        '^(?i)critical$' {
            if ($sev -ne "Critical") { return $false }
        }
        '^(?i)warning$' {
            if ($sev -notin @("Critical", "Warning")) { return $false }
        }
        '^(?i)security$' {
            if ($Category -notmatch '(?i)security') { return $false }
        }
        '^(?i)everything|info|information$' { }
        default {
            if ($sev -notin @("Critical", "Warning")) { return $false }
        }
    }

    $cats = @($ei.notifyCategories)
    if ($cats.Count -gt 0 -and $cats -notcontains "*" -and $cats -notcontains $Category) {
        return $false
    }
    return $true
}

function Get-LocSuppressionKey {
    param([object]$Incident, [object]$Rule)
    if ($Rule -and $Rule.suppressKey) { return [string]$Rule.suppressKey }
    return "inc|$($Incident.Title)|$($Incident.Category)"
}

function Test-LocSuppressed {
    param(
        [string]$Key,
        [int]$WindowSeconds = 3600
    )
    $items = @(Get-LocSuppressions)
    $now = Get-Date
    $cutoff = $now.AddSeconds(-1 * [Math]::Abs($WindowSeconds))
    $existing = $null
    $kept = @()
    foreach ($s in $items) {
        try {
            $last = [datetime]::Parse([string]$s.LastAt)
            if ($last -lt $cutoff) { continue }
        }
        catch { continue }
        if ($s.Key -eq $Key) { $existing = $s }
        $kept += $s
    }
    Save-LocSuppressions -Items $kept
    return $existing
}

function Update-LocSuppression {
    param(
        [string]$Key,
        [string]$Title,
        [int]$WindowSeconds = 3600
    )
    $items = @(Get-LocSuppressions)
    $found = $false
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $updated = @()
    foreach ($s in $items) {
        if ($s.Key -eq $Key) {
            $count = [int]$s.Count + 1
            $updated += [PSCustomObject]@{
                Key     = $Key
                Title   = $Title
                Count   = $count
                FirstAt = $s.FirstAt
                LastAt  = $now
                Window  = $WindowSeconds
            }
            $found = $true
        }
        else {
            $updated += $s
        }
    }
    if (-not $found) {
        $updated += [PSCustomObject]@{
            Key     = $Key
            Title   = $Title
            Count   = 1
            FirstAt = $now
            LastAt  = $now
            Window  = $WindowSeconds
        }
    }
    Save-LocSuppressions -Items $updated
    $match = $updated | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    return $match
}

function New-LocAlertRecord {
    param(
        [object]$Incident,
        [string]$Message,
        [int]$RepeatCount = 1,
        [bool]$Suppressed = $false
    )
    return [PSCustomObject]@{
        Id           = [guid]::NewGuid().ToString()
        IncidentId   = $Incident.Id
        Title        = $Incident.Title
        Message      = $Message
        Severity     = $Incident.Severity
        Category     = $Incident.Category
        Score        = $Incident.Score
        Timestamp    = (Get-Date).ToUniversalTime().ToString("o")
        Acknowledged = $false
        RepeatCount  = $RepeatCount
        Suppressed   = $Suppressed
    }
}

function Add-LocAlert {
    param([object]$Alert)
    $alerts = @(Get-LocStoredAlerts)
    $alerts = @($Alert) + @($alerts)
    if ($alerts.Count -gt 500) { $alerts = $alerts[0..499] }
    Save-LocStoredAlerts -Alerts $alerts
}

function Acknowledge-LocAlert {
    param([string]$Id, [string]$Operator = "operator")
    $alerts = @(Get-LocStoredAlerts)
    $found = $false
    foreach ($a in $alerts) {
        if ($a.Id -eq $Id) {
            $a | Add-Member -NotePropertyName Acknowledged -NotePropertyValue $true -Force
            $a | Add-Member -NotePropertyName AcknowledgedAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o")) -Force
            $found = $true
            break
        }
    }
    if (-not $found) {
        return New-ApiResult -Success $false -Message "Alert not found" -StatusCode 404
    }
    Save-LocStoredAlerts -Alerts $alerts
    Add-LocEventAudit -Action "AlertAck" -Operator $Operator -Data @{ Id = $Id }
    $alert = $alerts | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    return New-ApiResult -Success $true -Message "Acknowledged" -Data $alert
}
