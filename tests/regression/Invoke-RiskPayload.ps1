# tests/regression/Invoke-RiskPayload.ps1 — RiskEngine + AgentExecutionPayload validation
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $Root 'core\Engine.ps1')
Get-LocCoreEngineFiles -RootPath $Root | ForEach-Object { . $_ }
Initialize-LocSettings -RootPath $Root
Initialize-LocRiskEngine -RootPath $Root

$script:pass = 0
$script:fail = 0
function Assert-True {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

Write-Host 'Risk / payload validation' -ForegroundColor Cyan

$ok = Test-LocAgentExecutionPayload -Payload @{
    transactionId  = [guid]::NewGuid().ToString()
    targetAgentId  = 'agent-1'
    module         = 'activedirectory'
    action         = 'Get-ADUserStatus'
    riskLevel      = 'READ'
}
Assert-True 'valid ModuleAction payload' ([bool]$ok.Success)

$bad = Test-LocAgentExecutionPayload -Payload @{
    transactionId = [guid]::NewGuid().ToString()
    targetAgentId = 'agent-1'
    module = 'tools'
    action = 'evil'
    riskLevel = 'LOW'
    Script = 'Get-Process'
}
Assert-True 'rejects Script field' (-not $bad.Success)

$types = @(Get-LocFleetCommandTypes)
Assert-True 'ModuleAction allow-listed' ($types -contains 'ModuleAction')

$mods = @(Get-ChildItem (Join-Path $Root 'modules') -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'module.json')
    })
$need = @('ActiveDirectory','DNS','DHCP','GroupPolicy','HyperV','Certificates','ServerOperations')
foreach ($n in $need) {
    Assert-True "module folder $n" ($mods.Name -contains $n)
}

Write-Host "Result: $($script:pass) passed, $($script:fail) failed" -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail -gt 0) { exit 1 }
exit 0
