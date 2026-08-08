# core/PlaybookService.ps1 - Step runner with risk-gated approvals (extends AutomationEngine)

$script:LocPlaybookDefsPath = $null
$script:LocPlaybookDefs = @()

function Initialize-LocPlaybookService {
    param([string]$RootPath)
    if (-not $RootPath) { $RootPath = Get-LocRoot }
    $dir = Join-Path $RootPath 'data\playbooks'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $script:LocPlaybookDefsPath = $dir
    $defs = @()
    Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        try { $defs += (Get-Content $_.FullName -Raw | ConvertFrom-Json) } catch { Write-Debug $_.Exception.Message }
    }
    $script:LocPlaybookDefs = @($defs)
}

function Get-LocPlaybookDefinitions {
    if (-not $script:LocPlaybookDefsPath) { Initialize-LocPlaybookService }
    return @($script:LocPlaybookDefs)
}

function Get-LocPlaybookDefinition {
    param([Parameter(Mandatory)][string]$Id)
    return Get-LocPlaybookDefinitions | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
}

function Invoke-LocPlaybookSteps {
    param(
        [Parameter(Mandatory)][string]$PlaybookId,
        [hashtable]$Parameters = @{},
        [bool]$Approved = $false,
        [bool]$IsAdmin = $false,
        [string]$Operator = 'operator',
        [switch]$DryRun
    )

    $def = Get-LocPlaybookDefinition -Id $PlaybookId
    if (-not $def) {
        return New-ApiResult -Success $false -Message "Playbook not found: $PlaybookId" -StatusCode 404
    }

    $steps = @($def.steps)
    $results = New-Object System.Collections.ArrayList
    $blocked = $false

    foreach ($step in $steps) {
        $risk = if ($step.riskLevel) { [string]$step.riskLevel } else { 'READ' }
        $actionId = if ($step.action) { [string]$step.action } else { [string]$step.id }
        $kind = if ($step.kind) { [string]$step.kind } else { 'diagnostics' }

        $auth = Test-LocActionAuthorized -ActionId $actionId -RiskLevel $risk -IsAdmin $IsAdmin -Approved $Approved -Kind $kind
        if (-not $DryRun -and -not $auth.Success -and $risk -notin @('READ', 'SAFE')) {
            [void]$results.Add([ordered]@{
                    Step      = $actionId
                    RiskLevel = $risk
                    Status    = 'needs_approval'
                    Message   = $auth.Message
                    Approval  = $auth.Data
                })
            $blocked = $true
            break
        }

        if ($DryRun) {
            [void]$results.Add([ordered]@{
                    Step      = $actionId
                    RiskLevel = $risk
                    Status    = 'dry_run'
                    Module    = [string]$step.module
                    Kind      = $kind
                })
            continue
        }

        $stepResult = $null
        if ($step.module -and $actionId -and (Get-Command Invoke-LocModuleAction -ErrorAction SilentlyContinue)) {
            $stepResult = Invoke-LocModuleAction -ModuleId ([string]$step.module) -Kind $kind -ActionName $actionId -Params $Parameters -ForceRefresh $true
        }
        else {
            $stepResult = New-ApiResult -Success $true -Message "Step $actionId acknowledged (no module binding)"
        }

        [void]$results.Add([ordered]@{
                Step      = $actionId
                RiskLevel = $risk
                Status    = if ($stepResult.Success) { 'ok' } else { 'failed' }
                Message   = $stepResult.Message
                Data      = $stepResult.Data
            })

        if (-not $stepResult.Success -and $step.continueOnError -ne $true) {
            $blocked = $true
            break
        }
    }

    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'Playbook' -Category 'Execution' -Summary "Playbook $PlaybookId by $Operator" -Data @{
            Steps   = @($results)
            Blocked = $blocked
        } | Out-Null
    }

    return New-ApiResult -Success (-not $blocked) -Message $(if ($blocked) { 'Playbook stopped' } else { 'Playbook complete' }) -Data @{
        PlaybookId = $PlaybookId
        Steps      = @($results)
        Blocked    = $blocked
    }
}
