# core/SeverityEngine.ps1 - Score 0-100 and severity labels

function Get-LocSeverityBaseScore {
    param([string]$Severity)
    switch -Regex ($Severity) {
        '^(?i)critical$' { return 90 }
        '^(?i)warning$'  { return 55 }
        '^(?i)error$'    { return 75 }
        default          { return 20 }
    }
}

function Get-LocSeverityLabel {
    param([int]$Score)
    if ($Score -ge 80) { return "Critical" }
    if ($Score -ge 40) { return "Warning" }
    return "Information"
}

function Compute-LocIncidentScore {
    param(
        [Parameter(Mandatory)][object]$Incident,
        [object]$Rule = $null,
        [int]$ChainLength = 1,
        [int]$Recurrence = 1
    )

    $base = 40
    if ($Rule -and $Rule.score) {
        $base = [int]$Rule.score
    }
    elseif ($Rule -and $Rule.severity) {
        $base = Get-LocSeverityBaseScore -Severity ([string]$Rule.severity)
    }
    elseif ($Incident.Severity) {
        $base = Get-LocSeverityBaseScore -Severity ([string]$Incident.Severity)
    }

    $boost = 0
    $cat = [string]$Incident.Category
    if ($cat -match '(?i)security') { $boost += 10 }
    if ($ChainLength -gt 1) { $boost += [Math]::Min(25, ($ChainLength - 1) * 8) }
    if ($Recurrence -gt 5) { $boost += [Math]::Min(15, [int](($Recurrence - 5) / 2)) }

    $score = [Math]::Min(100, [Math]::Max(0, $base + $boost))
    $label = Get-LocSeverityLabel -Score $score

    return [PSCustomObject]@{
        Score    = $score
        Severity = $label
    }
}
