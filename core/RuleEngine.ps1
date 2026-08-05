# core/RuleEngine.ps1 - Load and evaluate JSON detection rules

$script:LocRules = @()
$script:LocRuleHits = [System.Collections.Hashtable]::Synchronized(@{})
$script:LocRulesPath = $null
$script:LocRulesLoadedAt = $null

function Get-LocRulesPath {
    if (-not $script:LocRulesPath) {
        $script:LocRulesPath = Join-Path (Get-LocRoot) "rules"
    }
    return $script:LocRulesPath
}

function Initialize-LocRuleEngine {
    $path = Get-LocRulesPath
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    Import-LocRules
}

function Import-LocRules {
    $path = Get-LocRulesPath
    $rules = @()
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter "*.json" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $obj = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $obj.id) { return }
                $obj | Add-Member -NotePropertyName _path -NotePropertyValue $_.FullName -Force
                $cat = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                if (-not $obj.category) {
                    $obj | Add-Member -NotePropertyName category -NotePropertyValue $cat -Force
                }
                $rules += $obj
            }
            catch {
                Write-LocLog -Module "EVENTINTEL" -Action "RuleLoad" -Level "WARN" -Message "Failed $($_.Exception.Message) for $($_.FullName)"
            }
        }
    }
    $script:LocRules = $rules
    $script:LocRulesLoadedAt = Get-Date
    Write-LocLog -Module "EVENTINTEL" -Action "RuleLoad" -Level "INFO" -Message "Loaded $($rules.Count) rule(s)"
}

function Get-LocRules {
    return @($script:LocRules)
}

function Test-LocRulesReload {
    $path = Get-LocRulesPath
    if (-not (Test-Path $path)) { return }
    $newest = Get-ChildItem -Path $path -Filter "*.json" -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { return }
    if (-not $script:LocRulesLoadedAt -or $newest.LastWriteTime -gt $script:LocRulesLoadedAt) {
        Import-LocRules
    }
}

function Clear-LocRuleHitWindow {
    param([string]$RuleId, [datetime]$Cutoff)
    $key = $RuleId
    if (-not $script:LocRuleHits.ContainsKey($key)) { return }
    $kept = @($script:LocRuleHits[$key] | Where-Object { $_ -ge $Cutoff })
    $script:LocRuleHits[$key] = [System.Collections.ArrayList]@($kept)
}

function Add-LocRuleHit {
    param([string]$RuleId, [datetime]$When = (Get-Date))
    if (-not $script:LocRuleHits.ContainsKey($RuleId)) {
        $script:LocRuleHits[$RuleId] = [System.Collections.ArrayList]::new()
    }
    [void]$script:LocRuleHits[$RuleId].Add($When)
}

function Get-LocRuleHitCount {
    param([string]$RuleId, [int]$WindowSeconds)
    $cutoff = (Get-Date).AddSeconds(-1 * [Math]::Abs($WindowSeconds))
    Clear-LocRuleHitWindow -RuleId $RuleId -Cutoff $cutoff
    if (-not $script:LocRuleHits.ContainsKey($RuleId)) { return 0 }
    return @($script:LocRuleHits[$RuleId]).Count
}

function Test-LocEventMatchesRule {
    param(
        [Parameter(Mandatory)][object]$Event,
        [Parameter(Mandatory)][object]$Rule
    )

    if ($Rule.enabled -eq $false) { return $false }

    if ($null -ne $Rule.eventId -and [int]$Rule.eventId -ne 0) {
        if ([int]$Event.EventID -ne [int]$Rule.eventId) { return $false }
    }

    if ($Rule.source) {
        $src = [string]$Rule.source
        if ($src -ne "*" -and [string]$Event.Source -notmatch [regex]::Escape($src) -and [string]$Event.Source -ne $src) {
            # allow case-insensitive exact or contains
            if ([string]$Event.Source -notlike "*$src*" -and [string]$Event.Source -ne $src) {
                if ([string]$Event.Source.ToLower() -ne $src.ToLower()) { return $false }
            }
        }
    }

    if ($Rule.category -and $Rule.matchCategory) {
        if ([string]$Event.Category -ne [string]$Rule.category) { return $false }
    }

    if ($Rule.messageContains) {
        $needle = [string]$Rule.messageContains
        if (-not [string]::IsNullOrWhiteSpace($needle)) {
            $msg = [string]$Event.Message
            if ($msg -notmatch [regex]::Escape($needle) -and $msg -notlike "*$needle*") {
                return $false
            }
        }
    }

    if ($Rule.healthMetric) {
        $metric = [string]$Rule.healthMetric
        $data = $Event.Data
        if (-not $data) { return $false }
        $val = $null
        if ($data -is [hashtable]) {
            if ($data.ContainsKey($metric)) { $val = $data[$metric] }
            elseif ($data.ContainsKey("healthMetric") -and [string]$data["healthMetric"] -eq $metric) { $val = $data["healthMetric"] }
        }
        else {
            if ($data.PSObject.Properties[$metric]) { $val = $data.$metric }
            elseif ($data.PSObject.Properties["healthMetric"] -and [string]$data.healthMetric -eq $metric) { $val = $data.healthMetric }
        }
        if ($null -eq $val) { return $false }
        if ($null -ne $Rule.thresholdMin -and [double]$val -lt [double]$Rule.thresholdMin) { return $false }
        if ($null -ne $Rule.thresholdMax -and [double]$val -gt [double]$Rule.thresholdMax) { return $false }
        if ($null -ne $Rule.equals -and [string]$val -ne [string]$Rule.equals) { return $false }
    }

    return $true
}

function Evaluate-LocEventRules {
    param([Parameter(Mandatory)][object]$Event)

    Test-LocRulesReload
    $hits = @()

    foreach ($rule in @($script:LocRules)) {
        if (-not (Test-LocEventMatchesRule -Event $Event -Rule $rule)) { continue }

        $threshold = if ($null -ne $rule.threshold) { [int]$rule.threshold } else { 1 }
        $window = if ($null -ne $rule.windowSeconds) { [int]$rule.windowSeconds } else { 300 }

        Add-LocRuleHit -RuleId ([string]$rule.id)
        $count = Get-LocRuleHitCount -RuleId ([string]$rule.id) -WindowSeconds $window

        if ($count -ge $threshold) {
            $hits += [PSCustomObject]@{
                Rule       = $rule
                HitCount   = $count
                WindowSecs = $window
                Event      = $Event
            }
        }
    }

    return $hits
}
