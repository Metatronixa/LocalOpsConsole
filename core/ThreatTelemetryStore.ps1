# ThreatTelemetryStore.ps1 - JSONL ring buffer (50k / 14-day TTL)
function Get-LocThreatDataDir {
    $root = if (Get-Command Get-LocRoot -ErrorAction SilentlyContinue) { Get-LocRoot } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
    $dir = Join-Path $root 'data\threat'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-LocThreatEventsPath { Join-Path (Get-LocThreatDataDir) 'events.jsonl' }
function Get-LocThreatMetaPath { Join-Path (Get-LocThreatDataDir) 'meta.json' }

function Get-LocThreatMeta {
    $path = Get-LocThreatMetaPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ Count = 0; OldestUtc = $null; UpdatedUtc = $null }
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return [PSCustomObject]@{ Count = 0; OldestUtc = $null; UpdatedUtc = $null }
    }
}

function Save-LocThreatMeta {
    param([object]$Meta)
    $path = Get-LocThreatMetaPath
    $json = ($Meta | ConvertTo-Json -Depth 4 -Compress)
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Add-LocThreatEventRecord {
    param([Parameter(Mandatory)][hashtable]$Record)
    $path = Get-LocThreatEventsPath
    $line = ($Record | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    $meta = Get-LocThreatMeta
    $count = [int]$meta.Count + 1
    $oldest = if ($meta.OldestUtc) { [string]$meta.OldestUtc } else { [string]$Record.timestamp }
    Save-LocThreatMeta -Meta ([PSCustomObject]@{
            Count      = $count
            OldestUtc  = $oldest
            UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        })
}

function Get-LocThreatEventRecords {
    param([int]$Max = 2000)
    $path = Get-LocThreatEventsPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $lines = @(Get-Content -LiteralPath $path -Tail $Max -ErrorAction SilentlyContinue)
    $items = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            [void]$items.Add($obj)
        }
        catch { Write-Debug $_.Exception.Message }
    }
    return @($items.ToArray())
}

function Invoke-LocThreatRingPrune {
    param(
        [int]$MaxKeep = 50000,
        [int]$RetentionDays = 14
    )
    $path = Get-LocThreatEventsPath
    if (-not (Test-Path -LiteralPath $path)) { return }
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $RetentionDays)
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            $ts = [datetime]::Parse([string]$obj.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if ($ts -lt $cutoff) { continue }
            $kept.Add($line) | Out-Null
        }
        catch { continue }
    }
    if ($kept.Count -gt $MaxKeep) {
        $kept = [System.Collections.Generic.List[string]]$kept.GetRange($kept.Count - $MaxKeep, $MaxKeep)
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($path, $kept.ToArray(), $utf8)
    $oldest = $null
    if ($kept.Count -gt 0) {
        try { $oldest = ([string](($kept[0] | ConvertFrom-Json).timestamp)) } catch { Write-Debug $_.Exception.Message }
    }
    Save-LocThreatMeta -Meta ([PSCustomObject]@{
            Count      = $kept.Count
            OldestUtc  = $oldest
            UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        })
}
