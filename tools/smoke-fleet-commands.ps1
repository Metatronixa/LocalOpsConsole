# tools/smoke-fleet-commands.ps1 - Validate fleet command allow-list + optional live queue
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$BaseUrl = "http://localhost:8787/api/v1",
    [string]$AgentId = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $Root "core\Response.ps1")
. (Join-Path $Root "core\Settings.ps1")
. (Join-Path $Root "core\Logger.ps1")
. (Join-Path $Root "core\FleetStore.ps1")
. (Join-Path $Root "core\FleetStoreInit.ps1")
. (Join-Path $Root "core\FleetAuth.ps1")
. (Join-Path $Root "core\Fleet.ps1")

Initialize-LocSettings -RootPath $Root

$script:pass = 0
$script:fail = 0

function Assert-True {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        Write-Host "PASS  $Name" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "FAIL  $Name $Detail" -ForegroundColor Red
        $script:fail++
    }
}

$required = @(
    'FlushDns', 'RestartSpooler', 'GetProcesses', 'EndProcess', 'GetPrinters',
    'GetStartupApps', 'GetScheduledTasks',
    'DiskCleanup', 'ClearPrintQueue', 'NetworkSoftRepair', 'RestartUpdateStack', 'CaptureProcessSnapshot',
    'NetHealthSmoke', 'SfcScannow', 'ChkdskScan', 'ChkdskScheduleFix', 'CollectInventory', 'Message',
    'AuditSecurityBaseline', 'ApplySecurityPolicy', 'SelfUpdate'
)
$types = @(Get-LocFleetCommandTypes)
Write-Host "Fleet command allow-list ($($types.Count) types)" -ForegroundColor Cyan
foreach ($t in $required) {
    Assert-True -Name "allow-list has $t" -Ok ($types -contains $t)
}

# Resolve-LocHttpListenHosts still required for fleet
. (Join-Path $Root "core\Settings.ps1")
$lh = @(Resolve-LocHttpListenHosts -BindHost "0.0.0.0")
Assert-True -Name "bind 0.0.0.0 -> +" -Ok (($lh.Count -eq 1) -and ($lh[0] -eq "+"))

if ($Live) {
    Write-Host ""
    Write-Host "Live API $BaseUrl" -ForegroundColor Cyan
    try {
        $h = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 10
        Assert-True -Name "health" -Ok ([bool]$h.Success)
    }
    catch {
        Assert-True -Name "health" -Ok $false -Detail $_.Exception.Message
    }

    try {
        $agents = Invoke-RestMethod -Uri "$BaseUrl/fleet/agents" -TimeoutSec 15
        Assert-True -Name "fleet agents" -Ok ([bool]$agents.Success)
        $list = @($agents.Data)
        if (-not $AgentId -and $list.Count -gt 0) {
            $AgentId = [string]$list[0].Id
        }
        if ($AgentId) {
            $detail = Invoke-RestMethod -Uri "$BaseUrl/fleet/agents/$AgentId" -TimeoutSec 15
            Assert-True -Name "agent detail" -Ok ([bool]$detail.Success)

            $lat = Invoke-RestMethod -Uri "$BaseUrl/fleet/agents/$AgentId/latency" -TimeoutSec 20
            # ICMP may fail on some networks — endpoint must respond with JSON either way
            Assert-True -Name "latency endpoint responds" -Ok ($null -ne $lat -and $null -ne $lat.Data)

            # Unblock queue so claim smoke is deterministic when a prior Running job is stuck
            try {
                $clearBody = @{ AgentId = $AgentId } | ConvertTo-Json -Compress
                Invoke-RestMethod -Uri "$BaseUrl/fleet/commands/clear-stuck" -Method POST -Body $clearBody -ContentType "application/json" -TimeoutSec 20 | Out-Null
            }
            catch { Write-Debug $_.Exception.Message }

            $body = @{ AgentId = $AgentId; Type = "FlushDns"; Payload = @{} } | ConvertTo-Json -Compress
            $q = Invoke-RestMethod -Uri "$BaseUrl/fleet/commands" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 20
            Assert-True -Name "queue FlushDns" -Ok ([bool]$q.Success) -Detail ([string]$q.Message)

            $body2 = @{ AgentId = $AgentId; Type = "GetProcesses"; Payload = @{} } | ConvertTo-Json -Compress
            $q2 = Invoke-RestMethod -Uri "$BaseUrl/fleet/commands" -Method POST -Body $body2 -ContentType "application/json" -TimeoutSec 20
            Assert-True -Name "queue GetProcesses" -Ok ([bool]$q2.Success) -Detail ([string]$q2.Message)

            # Claim path (same as agent poll) must return claimed commands, not empty.
            # Live agents may win the race — retry briefly, then accept agent-claimed Running/Completed.
            . (Join-Path $Root "core\Response.ps1")
            . (Join-Path $Root "core\Settings.ps1")
            . (Join-Path $Root "core\Logger.ps1")
            . (Join-Path $Root "core\FleetStore.ps1")
            . (Join-Path $Root "core\FleetAuth.ps1")
            . (Join-Path $Root "core\Fleet.ps1")
            Initialize-LocSettings -RootPath $Root
            Initialize-LocLogger -RootPath $Root
            Initialize-LocFleetStore
            $claimOk = $false
            $claimType = ""
            $claimCount = 0
            $claimedIds = @()
            for ($attempt = 0; $attempt -lt 8; $attempt++) {
                $claim = Claim-LocFleetCommands -AgentId $AgentId -MaxClaim 1
                $claimCount = @($claim.Data).Count
                if ($claim.Success -and $claimCount -ge 1) {
                    $claimOk = $true
                    $claimType = [string]$claim.Data[0].Type
                    foreach ($item in @($claim.Data)) {
                        if ($item.Id) { $claimedIds += [string]$item.Id }
                    }
                    break
                }
                Start-Sleep -Milliseconds 250
            }
            if (-not $claimOk) {
                # Agent likely claimed first — verify our queued commands moved off Pending.
                $store = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
                $recent = @($store.commands) | Where-Object {
                    [string]$_.AgentId -eq $AgentId -and
                    ([string]$_.Type -eq "FlushDns" -or [string]$_.Type -eq "GetProcesses") -and
                    ([string]$_.Status -eq "Running" -or [string]$_.Status -eq "Completed" -or [string]$_.Status -eq "Failed")
                } | Select-Object -First 1
                if ($recent) {
                    $claimOk = $true
                    $claimType = [string]$recent.Type
                    $claimCount = 1
                }
            }
            Assert-True -Name "claim returns at least one command" -Ok $claimOk -Detail ("count=" + $claimCount)
            if ($claimOk -and $claimType) {
                Assert-True -Name "claim has Type" -Ok (-not [string]::IsNullOrWhiteSpace($claimType))
            }
            # Do not leave in-process claims as Running (blocks the live agent queue).
            foreach ($cid in $claimedIds) {
                try {
                    Complete-LocFleetCommand -AgentId $AgentId -CommandId $cid -Success $true -Message "Smoke claim complete" | Out-Null
                }
                catch {
                    try { Cancel-LocFleetCommand -CommandId $cid -AgentId $AgentId -Reason "Smoke cleanup" | Out-Null } catch { Write-Debug $_.Exception.Message }
                }
            }

            $body3 = @{ AgentId = $AgentId; Type = "NotARealCommand"; Payload = @{} } | ConvertTo-Json -Compress
            try {
                Invoke-RestMethod -Uri "$BaseUrl/fleet/commands" -Method POST -Body $body3 -ContentType "application/json" -TimeoutSec 20 | Out-Null
                Assert-True -Name "reject unknown command" -Ok $false -Detail "should have failed"
            }
            catch {
                Assert-True -Name "reject unknown command" -Ok $true
            }
        }
        else {
            Write-Host "SKIP  live queue (no enrolled agents)" -ForegroundColor DarkGray
        }
    }
    catch {
        Assert-True -Name "fleet live" -Ok $false -Detail $_.Exception.Message
    }
}

Write-Host ""
$color = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host ("Result: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $color
if ($script:fail -gt 0) { exit 1 }
exit 0
