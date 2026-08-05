# core/CorrelationEngine.ps1 - Group rule hits into incidents / playbook chains

$script:LocCorrelationChains = @(
    [PSCustomObject]@{
        id       = "malware-chain"
        title    = "Possible Malware Infection"
        severity = "Critical"
        score    = 95
        category = "security"
        windowSeconds = 1800
        rules    = @("defender-disabled", "firewall-disabled", "powershell-encoded", "service-installed")
        minHits  = 3
    },
    [PSCustomObject]@{
        id       = "brute-force-chain"
        title    = "Brute Force Attack"
        severity = "Critical"
        score    = 90
        category = "security"
        windowSeconds = 600
        rules    = @("failed-login", "account-locked")
        minHits  = 1
        requireAll = $false
        escalateFrom = "failed-login"
    }
)

$script:LocRecentRuleFires = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

function Register-LocRuleFire {
    param(
        [string]$RuleId,
        [string]$IncidentTitle,
        [datetime]$When = (Get-Date)
    )
    [void]$script:LocRecentRuleFires.Add([PSCustomObject]@{
            RuleId    = $RuleId
            Title     = $IncidentTitle
            Timestamp = $When
        })
    # prune older than 1 hour
    $cutoff = (Get-Date).AddHours(-1)
    $kept = @($script:LocRecentRuleFires | Where-Object { $_.Timestamp -ge $cutoff })
    $script:LocRecentRuleFires.Clear()
    foreach ($k in $kept) { [void]$script:LocRecentRuleFires.Add($k) }
}

function Find-LocOpenIncidentForRule {
    param(
        [string]$RuleId,
        [string]$Title,
        [string]$CorrelationKey = ""
    )
    $active = Get-LocIncidentFiles -Status "active"
    foreach ($inc in $active) {
        if ($CorrelationKey -and $inc.CorrelationKey -eq $CorrelationKey) { return $inc }
        if ($inc.RuleId -eq $RuleId -and $inc.Status -eq "Open") { return $inc }
        if ($Title -and $inc.Title -eq $Title -and $inc.Status -eq "Open") { return $inc }
    }
    return $null
}

function Test-LocCorrelationChains {
    param([string]$TriggeredRuleId)

    $results = @()
    foreach ($chain in $script:LocCorrelationChains) {
        $window = if ($chain.windowSeconds) { [int]$chain.windowSeconds } else { 1800 }
        $cutoff = (Get-Date).AddSeconds(-1 * $window)
        $fired = @($script:LocRecentRuleFires | Where-Object {
                $_.Timestamp -ge $cutoff -and ($chain.rules -contains $_.RuleId)
            })
        $uniqueRules = @($fired.RuleId | Select-Object -Unique)
        $minHits = if ($null -ne $chain.minHits) { [int]$chain.minHits } else { $chain.rules.Count }

        $ok = $false
        if ($chain.requireAll) {
            $ok = ($uniqueRules.Count -ge $chain.rules.Count)
        }
        else {
            $ok = ($uniqueRules.Count -ge $minHits) -and ($TriggeredRuleId -in $chain.rules -or $TriggeredRuleId -eq $chain.escalateFrom)
        }

        if ($ok) {
            $results += [PSCustomObject]@{
                Chain      = $chain
                FiredRules = $uniqueRules
                HitCount   = $fired.Count
            }
        }
    }
    return $results
}

function Resolve-LocCorrelationKey {
    param(
        [object]$Rule,
        [object]$Event
    )
    if ($Rule.correlationKey) { return [string]$Rule.correlationKey }
    $title = if ($Rule.incident) { [string]$Rule.incident } else { [string]$Rule.id }
    return "$($Rule.id)|$title"
}
