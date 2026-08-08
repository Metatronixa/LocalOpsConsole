# tests/regression/Invoke-ContractBaseline.ps1 — offline contract harness (no server)
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $Root 'core\Response.ps1')
. (Join-Path $Root 'core\Settings.ps1')
. (Join-Path $Root 'core\Logger.ps1')
. (Join-Path $Root 'core\Engine.ps1')
Get-LocCoreEngineFiles -RootPath $Root | Where-Object { $_ -match '[\\/]Fleet[^\\/]*\.ps1$' } | ForEach-Object { . $_ }
Initialize-LocSettings -RootPath $Root

$script:pass = 0
$script:fail = 0

function Assert-True {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) {
        Write-Host "PASS  $Name" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "FAIL  $Name $Detail" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host 'Contract baseline (offline)' -ForegroundColor Cyan

Assert-True -Name 'CONTRACT_BASELINE.md exists' -Ok (Test-Path (Join-Path $Root 'docs\CONTRACT_BASELINE.md'))

$manifests = @(Get-ChildItem -Path (Join-Path $Root 'modules') -Filter 'module.json' -Recurse -File)
Assert-True -Name 'module manifests >= 20' -Ok ($manifests.Count -ge 20) -Detail "count=$($manifests.Count)"
$badId = @($manifests | ForEach-Object {
        $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$j.id)) { $_.FullName }
    })
Assert-True -Name 'all module.json have id' -Ok ($badId.Count -eq 0) -Detail ($badId -join '; ')

$types = @(Get-LocFleetCommandTypes)
$required = @(
    'FlushDns', 'RestartSpooler', 'RunScript', 'GetProcesses', 'EndProcess',
    'CollectInventory', 'SelfUpdate', 'AuditSecurityBaseline', 'ApplySecurityPolicy', 'ModuleAction'
)
foreach ($t in $required) {
    Assert-True -Name "fleet allow-list has $t" -Ok ($types -contains $t)
}

Assert-True -Name 'New-ApiResult exists' -Ok ([bool](Get-Command New-ApiResult -ErrorAction SilentlyContinue))
Assert-True -Name 'Send-JsonResponse exists' -Ok ([bool](Get-Command Send-JsonResponse -ErrorAction SilentlyContinue))

$oversized = @(Get-ChildItem -Path (Join-Path $Root 'core'), (Join-Path $Root 'api'), (Join-Path $Root 'agent') `
        -Recurse -Include *.ps1, *.psm1 -ErrorAction SilentlyContinue |
        Where-Object { (Get-Content $_.FullName).Count -gt 250 })
$fleetOver = @($oversized | Where-Object {
        $_.Name -like 'Fleet*.ps1' -and $_.Name -notin @('FleetStore.ps1', 'FleetAuth.ps1')
    })
Assert-True -Name 'Fleet business modules each <= 250 lines' -Ok ($fleetOver.Count -eq 0) -Detail (
    ($fleetOver | ForEach-Object { '{0}={1}' -f $_.Name, (Get-Content $_.FullName).Count }) -join '; '
)

Write-Host ''
Write-Host "Result: $($script:pass) passed, $($script:fail) failed" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail -gt 0) { exit 1 }
exit 0
