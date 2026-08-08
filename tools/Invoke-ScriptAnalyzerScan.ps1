# tools/Invoke-ScriptAnalyzerScan.ps1 - Offline PSScriptAnalyzer scan for LocalOpsConsole
[CmdletBinding()]
param(
    [string[]]$Path = @('api', 'core', 'agent', 'modules', 'tools', 'scripts', 'tests'),
    [ValidateSet('Error', 'Warning', 'Information')]
    [string]$FailOn = 'Error',
    [switch]$SummaryOnly
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$SettingsPath = Join-Path $Root 'PSScriptAnalyzerSettings.psd1'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Error "PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser"
}

Import-Module PSScriptAnalyzer -ErrorAction Stop

$severityRank = @{ Error = 3; Warning = 2; Information = 1 }
$failRank = $severityRank[$FailOn]

$targets = foreach ($rel in $Path) {
    $full = Join-Path $Root $rel
    if (Test-Path -LiteralPath $full) { $full }
    else { Write-Warning "Skip missing path: $rel" }
}

if (-not $targets) {
    Write-Error "No scan paths found under $Root"
}

Write-Host "PSScriptAnalyzer scan" -ForegroundColor Cyan
Write-Host "  settings: $SettingsPath"
Write-Host "  paths:    $($targets -join ', ')"
Write-Host "  failOn:   $FailOn"
Write-Host ""

$all = @()
foreach ($t in $targets) {
    $all += @(Invoke-ScriptAnalyzer -Path $t -Recurse -Settings $SettingsPath -ErrorAction SilentlyContinue)
}

$grouped = $all | Group-Object RuleName | Sort-Object Count -Descending
$bySev = $all | Group-Object Severity

Write-Host "Findings: $($all.Count)" -ForegroundColor $(if ($all.Count) { 'Yellow' } else { 'Green' })
foreach ($g in $bySev) {
    Write-Host ("  {0,-12} {1}" -f $g.Name, $g.Count)
}

if (-not $SummaryOnly -and $all.Count -gt 0) {
    Write-Host ""
    $all |
        Sort-Object Severity, ScriptName, Line |
        Select-Object Severity, RuleName, ScriptName, Line, Message |
        Format-Table -AutoSize -Wrap
}

if ($grouped.Count -gt 0) {
    Write-Host ""
    Write-Host "Top rules:" -ForegroundColor Cyan
    $grouped | Select-Object -First 15 | ForEach-Object {
        Write-Host ("  {0,4}  {1}" -f $_.Count, $_.Name)
    }
}

$blocking = @($all | Where-Object { $severityRank[$_.Severity.ToString()] -ge $failRank })
if ($blocking.Count -gt 0) {
    Write-Host ""
    Write-Host "FAIL  $($blocking.Count) finding(s) at/above $FailOn" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "PASS  No findings at/above $FailOn" -ForegroundColor Green
exit 0
