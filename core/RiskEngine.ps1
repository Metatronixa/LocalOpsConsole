# core/RiskEngine.ps1 - Action risk classification & authorization guardrails

$script:LocRiskMatrix = $null
$script:LocRiskMatrixPath = $null

function Initialize-LocRiskEngine {
    param([string]$RootPath)
    if (-not $RootPath) { $RootPath = Get-LocRoot }
    $path = Join-Path $RootPath 'config\risk-matrix.json'
    $script:LocRiskMatrixPath = $path
    if (-not (Test-Path -LiteralPath $path)) {
        $script:LocRiskMatrix = @{
            tiers    = @{}
            defaults = @{ diagnostics = 'READ'; actions = 'LOW' }
            actions  = @{}
        }
        return
    }
    try {
        $script:LocRiskMatrix = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        Write-LocLog -Module 'CORE' -Action 'RiskEngine' -Level 'ERROR' -Message $_.Exception.Message
        $script:LocRiskMatrix = @{
            tiers    = @{}
            defaults = @{ diagnostics = 'READ'; actions = 'LOW' }
            actions  = @{}
        }
    }
}

function Get-LocRiskMatrix {
    if (-not $script:LocRiskMatrix) { Initialize-LocRiskEngine }
    return $script:LocRiskMatrix
}

function Get-LocActionRiskLevel {
    param(
        [string]$ActionId,
        [string]$Kind = 'actions'
    )
    $m = Get-LocRiskMatrix
    $actions = $m.actions
    if ($actions -and $ActionId) {
        $prop = $actions.PSObject.Properties | Where-Object { $_.Name -eq $ActionId } | Select-Object -First 1
        if ($prop -and $prop.Value.riskLevel) {
            return [string]$prop.Value.riskLevel
        }
    }
    $defaults = $m.defaults
    if ($Kind -eq 'diagnostics') {
        if ($defaults -and $defaults.diagnostics) { return [string]$defaults.diagnostics }
        return 'READ'
    }
    if ($defaults -and $defaults.actions) { return [string]$defaults.actions }
    return 'LOW'
}

function Get-LocRiskTierInfo {
    param([Parameter(Mandatory)][string]$RiskLevel)
    $m = Get-LocRiskMatrix
    $level = $RiskLevel.ToUpperInvariant()
    if ($m.tiers) {
        $prop = $m.tiers.PSObject.Properties | Where-Object { $_.Name -eq $level } | Select-Object -First 1
        if ($prop) { return $prop.Value }
    }
    return $null
}

function Test-LocRiskLevelValid {
    param([string]$RiskLevel)
    $valid = @('READ', 'SAFE', 'LOW', 'MODERATE', 'HIGH', 'CRITICAL')
    return ($valid -contains ([string]$RiskLevel).ToUpperInvariant())
}

function Test-LocActionAuthorized {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [string]$RiskLevel = '',
        [bool]$IsAdmin = $false,
        [bool]$Approved = $false,
        [string]$Kind = 'actions'
    )

    if (-not $RiskLevel) {
        $RiskLevel = Get-LocActionRiskLevel -ActionId $ActionId -Kind $Kind
    }
    $level = $RiskLevel.ToUpperInvariant()
    if (-not (Test-LocRiskLevelValid -RiskLevel $level)) {
        return New-ApiResult -Success $false -Message "Invalid risk level: $RiskLevel" -StatusCode 400
    }

    $tier = Get-LocRiskTierInfo -RiskLevel $level
    $needsAdmin = $false
    $approval = 'none'
    if ($tier) {
        if ($null -ne $tier.requiresAdmin) { $needsAdmin = [bool]$tier.requiresAdmin }
        if ($tier.approval) { $approval = [string]$tier.approval }
    }

    $m = Get-LocRiskMatrix
    if ($m.actions) {
        $prop = $m.actions.PSObject.Properties | Where-Object { $_.Name -eq $ActionId } | Select-Object -First 1
        if ($prop -and $null -ne $prop.Value.requiresAdmin) {
            $needsAdmin = [bool]$prop.Value.requiresAdmin
        }
    }

    if ($needsAdmin -and -not $IsAdmin) {
        return New-ApiResult -Success $false -Message "Action $ActionId requires elevation ($level)" -Data @{
            RiskLevel = $level
            Approval  = $approval
        } -StatusCode 403
    }

    if ($approval -ne 'none' -and -not $Approved -and $level -notin @('READ', 'SAFE')) {
        return New-ApiResult -Success $false -Message "Action $ActionId requires approval ($approval)" -Data @{
            RiskLevel       = $level
            Approval        = $approval
            RequiresApproval = $true
        } -StatusCode 403
    }

    return New-ApiResult -Success $true -Message 'Authorized' -Data @{
        RiskLevel = $level
        Approval  = $approval
    }
}

function Test-LocAgentExecutionPayload {
    param($Payload)

    if ($null -eq $Payload) {
        return New-ApiResult -Success $false -Message 'Payload required' -StatusCode 400
    }

    $forbidden = @('Script', 'ScriptText', 'Command', 'RawScript', 'PowerShell', 'Code')
    foreach ($name in $forbidden) {
        $has = $false
        if ($Payload -is [hashtable]) {
            $has = $Payload.ContainsKey($name)
        }
        elseif ($Payload.PSObject.Properties[$name]) {
            $has = $true
        }
        if ($has) {
            return New-ApiResult -Success $false -Message "Unstructured script field '$name' is forbidden" -StatusCode 400
        }
    }

    $get = {
        param($obj, $key)
        if ($obj -is [hashtable]) {
            if ($obj.ContainsKey($key)) { return $obj[$key] }
            return $null
        }
        $p = $obj.PSObject.Properties[$key]
        if ($p) { return $p.Value }
        return $null
    }

    $transactionId = & $get $Payload 'transactionId'
    $targetAgentId = & $get $Payload 'targetAgentId'
    $module = & $get $Payload 'module'
    $action = & $get $Payload 'action'
    $riskLevel = & $get $Payload 'riskLevel'

    if ([string]::IsNullOrWhiteSpace([string]$transactionId) -or
        [string]::IsNullOrWhiteSpace([string]$targetAgentId) -or
        [string]::IsNullOrWhiteSpace([string]$module) -or
        [string]::IsNullOrWhiteSpace([string]$action) -or
        [string]::IsNullOrWhiteSpace([string]$riskLevel)) {
        return New-ApiResult -Success $false -Message 'transactionId, targetAgentId, module, action, riskLevel required' -StatusCode 400
    }

    if (-not (Test-LocRiskLevelValid -RiskLevel ([string]$riskLevel))) {
        return New-ApiResult -Success $false -Message "Invalid riskLevel: $riskLevel" -StatusCode 400
    }

    return New-ApiResult -Success $true -Message 'Payload valid' -Data @{
        transactionId  = [string]$transactionId
        targetAgentId  = [string]$targetAgentId
        module         = [string]$module
        action         = [string]$action
        riskLevel      = ([string]$riskLevel).ToUpperInvariant()
        parameters     = (& $get $Payload 'parameters')
        requiresApproval = [bool](& $get $Payload 'requiresApproval')
    }
}
