# tests/regression/Invoke-FileLengthGate.ps1 — ≤250 lines for core/api/agent
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$oversized = @(Get-ChildItem -Path (Join-Path $Root 'core'), (Join-Path $Root 'api'), (Join-Path $Root 'agent') `
        -Recurse -Include *.ps1, *.psm1 -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content $_.FullName).Count -gt 250 })

Write-Host 'File length gate (core/api/agent <= 250)' -ForegroundColor Cyan
if ($oversized.Count -eq 0) {
    Write-Host 'PASS  no oversized files' -ForegroundColor Green
    exit 0
}

foreach ($f in $oversized) {
    $rel = $f.FullName.Replace($Root + '\', '')
    $n = (Get-Content $f.FullName).Count
    Write-Host "FAIL  $rel ($n lines)" -ForegroundColor Red
}
exit 1
