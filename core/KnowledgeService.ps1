# core/KnowledgeService.ps1 - Detect -> Diagnose -> Explain -> Recommend -> Repair -> Verify -> Record

$script:LocKnowledgePath = $null
$script:LocKnowledgeEntries = @()

function Initialize-LocKnowledgeService {
    param([string]$RootPath)
    if (-not $RootPath) { $RootPath = Get-LocRoot }
    $dir = Join-Path $RootPath 'data\knowledge'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $script:LocKnowledgePath = $dir
    $entries = @()
    Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $entries += (Get-Content $_.FullName -Raw | ConvertFrom-Json)
        }
        catch { Write-Debug $_.Exception.Message }
    }
    $script:LocKnowledgeEntries = @($entries)
}

function Get-LocKnowledgeEntries {
    if (-not $script:LocKnowledgePath) { Initialize-LocKnowledgeService }
    return @($script:LocKnowledgeEntries)
}

function Find-LocKnowledgeMatch {
    param(
        [string]$Symptom,
        [string]$Module = '',
        [object]$DiagnosticData = $null
    )
    $null = $DiagnosticData
    $entries = Get-LocKnowledgeEntries
    $sym = [string]$Symptom
    foreach ($e in $entries) {
        $ok = $true
        if ($Module -and $e.module -and ([string]$e.module).ToLower() -ne $Module.ToLower()) { $ok = $false }
        if ($ok -and $e.match -and $e.match.symptom) {
            if ($sym -notmatch [string]$e.match.symptom) { $ok = $false }
        }
        if ($ok) { return $e }
    }
    return $null
}

function Invoke-LocKnowledgePipeline {
    param(
        [Parameter(Mandatory)][string]$Symptom,
        [string]$Module = '',
        [object]$DiagnosticData = $null,
        [string]$Operator = 'operator'
    )

    $match = Find-LocKnowledgeMatch -Symptom $Symptom -Module $Module -DiagnosticData $DiagnosticData
    $pipeline = [ordered]@{
        Detect    = @{ Symptom = $Symptom; Module = $Module; At = (Get-Date).ToUniversalTime().ToString('o') }
        Diagnose  = $null
        Explain   = $null
        Recommend = $null
        Repair    = $null
        Verify    = $null
        Record    = $null
    }

    if ($match) {
        $pipeline.Diagnose = $match.diagnose
        $pipeline.Explain = $match.explain
        $pipeline.Recommend = $match.recommend
        $pipeline.Repair = $match.repair
        $pipeline.Verify = $match.verify
    }
    else {
        $pipeline.Diagnose = @{ Status = 'unknown'; Message = 'No knowledge entry matched' }
        $pipeline.Explain = 'Insufficient mapped knowledge for this symptom.'
        $pipeline.Recommend = @('Gather more diagnostics', 'Check recent timeline events')
    }

    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'Knowledge' -Category 'Analysis' -Summary "Knowledge pipeline: $Symptom" -Data $pipeline | Out-Null
    }

    $pipeline.Record = @{
        Operator = $Operator
        KnowledgeId = if ($match) { [string]$match.id } else { $null }
        RecordedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    return New-ApiResult -Success $true -Message 'Knowledge pipeline complete' -Data $pipeline
}
