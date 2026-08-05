# core/Timeline.ps1 - Incident and global timeline helpers

function Add-LocTimelineEntry {
    param(
        [Parameter(Mandatory)][object]$Incident,
        [Parameter(Mandatory)][string]$Type,
        [string]$Title = "",
        [string]$Detail = "",
        [string]$Severity = "",
        [hashtable]$Data = @{}
    )

    $entry = [PSCustomObject]@{
        Id        = [guid]::NewGuid().ToString()
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        Type      = $Type
        Title     = $Title
        Detail    = $Detail
        Severity  = $Severity
        Data      = $Data
    }

    $list = @()
    if ($Incident.Timeline) { $list = @($Incident.Timeline) }
    $list += $entry
    $Incident | Add-Member -NotePropertyName Timeline -NotePropertyValue $list -Force
    return $entry
}

function Get-LocGlobalTimeline {
    param([int]$Max = 100, [int]$Hours = 24)
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-1 * [Math]::Abs($Hours))
    $entries = @()

    $events = Get-LocStoredEvents -Max 500
    foreach ($e in $events) {
        try {
            $ts = [datetime]::Parse([string]$e.Timestamp).ToUniversalTime()
            if ($ts -lt $cutoff) { continue }
        }
        catch { continue }
        $entries += [PSCustomObject]@{
            Timestamp = $e.Timestamp
            Type      = "event"
            Title     = if ($e.Message) { $e.Message } else { "$($e.Source) $($e.EventID)" }
            Severity  = $e.Severity
            Category  = $e.Category
            Source    = $e.Source
            EventID   = $e.EventID
            IncidentId = $null
        }
    }

    foreach ($inc in @(Get-LocIncidentFiles -Status "all")) {
        foreach ($t in @($inc.Timeline)) {
            try {
                $ts = [datetime]::Parse([string]$t.Timestamp).ToUniversalTime()
                if ($ts -lt $cutoff) { continue }
            }
            catch { continue }
            $entries += [PSCustomObject]@{
                Timestamp  = $t.Timestamp
                Type       = $t.Type
                Title      = $t.Title
                Severity   = if ($t.Severity) { $t.Severity } else { $inc.Severity }
                Category   = $inc.Category
                Source     = "Incident"
                EventID    = 0
                IncidentId = $inc.Id
            }
        }
    }

    return @($entries | Sort-Object Timestamp -Descending | Select-Object -First $Max)
}
