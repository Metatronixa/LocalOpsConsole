# tools/smoke-threat-telemetry.ps1 - Offline threat ingest + decode contract
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent

. (Join-Path $Root 'core\Response.ps1')
. (Join-Path $Root 'core\Settings.ps1')
. (Join-Path $Root 'core\Logger.ps1')
Initialize-LocSettings -RootPath $Root
Initialize-LocLogger -RootPath $Root

. (Join-Path $Root 'core\ScriptBlockDecoder.ps1')
. (Join-Path $Root 'core\ThreatSeverity.ps1')
. (Join-Path $Root 'core\ThreatTelemetryStore.ps1')
. (Join-Path $Root 'core\ThreatTelemetryService.ps1')
. (Join-Path $Root 'core\ThreatKnowledgeEngine.ps1')
. (Join-Path $Root 'agent\EnvironmentProfileDetector.ps1')

$script:pass = 0
$script:fail = 0
function Assert-True {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

Write-Host 'Threat telemetry offline checks' -ForegroundColor Cyan

$profile = Get-LocAgentEnvironmentProfile
Assert-True -Name 'profile enum' -Ok ($profile -in @(Get-LocThreatAllowedProfiles)) -Detail $profile

# Base64 sample: $a = 'nhack'  -> use a known decode
# JGEgPSAnbmhhY2sn  is `$a = 'nhack'` in UTF8 base64? Plan sample was JGFAICA9ICduaGFjayc=
$sampleB64 = 'JGEgPSAnbmhhY2sn'
$dec = Invoke-LocScriptBlockDecode -RawText $sampleB64 -IsEncoded $true
Assert-True -Name 'base64 decode matched' -Ok ([bool]$dec.WasDecoded)
Assert-True -Name 'decode never empty when matched' -Ok (-not [string]::IsNullOrWhiteSpace([string]$dec.DecodedText))

$batch = @{
    agentId            = 'TEST-AGENT-01'
    computerName       = 'DC-01'
    environmentProfile = 'DomainController'
    batchTimestamp     = (Get-Date).ToUniversalTime().ToString('o')
    events             = @(
        @{
            eventId            = 4104
            transactionId      = [guid]::NewGuid().Guid
            timestamp          = (Get-Date).ToUniversalTime().ToString('o')
            severity           = 'HIGH'
            userIdentity       = 'test'
            processName        = 'powershell.exe'
            serviceName        = ''
            scriptBlockId      = 'sb-1'
            rawScriptBlockText = $sampleB64
            isEncoded          = $true
        }
    )
}

$result = Invoke-LocThreatTelemetryIngest -AgentId 'TEST-AGENT-01' -Batch $batch
Assert-True -Name 'ingest success' -Ok ([bool]$result.Success) -Detail $result.Message
Assert-True -Name 'processed count' -Ok ($result.Data.Processed -ge 1)

$firstEv = ConvertTo-LocThreatEventHashtable -Event $batch.events[0]
$txId = [string]$firstEv['transactionId']
$rows = @(Get-LocThreatEventRecords -Max 50)
$hit = $null
foreach ($r in $rows) {
    $rid = [string]($r | Select-Object -ExpandProperty transactionId -ErrorAction SilentlyContinue)
    if ($rid -eq $txId) { $hit = $r; break }
}
Assert-True -Name 'row persisted' -Ok ($null -ne $hit) -Detail ("tx=$txId rows=$($rows.Count)")
if ($null -ne $hit) {
    $decodedStored = [string]($hit | Select-Object -ExpandProperty decodedScriptBlockText -ErrorAction SilentlyContinue)
    Assert-True -Name 'decoded stored' -Ok (-not [string]::IsNullOrWhiteSpace($decodedStored))
    $sev = [string]($hit | Select-Object -ExpandProperty severity -ErrorAction SilentlyContinue)
    Assert-True -Name 'DC severity elevated' -Ok (@('HIGH', 'CRITICAL') -contains $sev) -Detail $sev
}

# Ensure no Invoke-Expression of payload in decoder source
$decSrc = Get-Content (Join-Path $Root 'core\ScriptBlockDecoder.ps1') -Raw
Assert-True -Name 'decoder has no Invoke-Expression call' -Ok ($decSrc -notmatch '(?i)Invoke-Expression\s|^\s*IEX\s')

Write-Host ""
Write-Host ("Result: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
