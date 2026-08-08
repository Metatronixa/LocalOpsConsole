# CommandDispatcher.ps1 - Invoke-AgentCommand switch + ModuleAction

function Get-LocAgentModulesRoot {
    if ($script:LocAgentModulesRoot -and (Test-Path -LiteralPath $script:LocAgentModulesRoot)) {
        return $script:LocAgentModulesRoot
    }
    $candidates = @(
        (Join-Path $script:LocAgentDir 'modules'),
        (Join-Path (Split-Path $script:LocAgentDir -Parent) 'modules')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    $probe = Split-Path $script:LocAgentDir -Parent
    for ($i = 0; $i -lt 4 -and $probe; $i++) {
        $m = Join-Path $probe 'modules'
        if (Test-Path -LiteralPath $m) { return (Resolve-Path -LiteralPath $m).Path }
        $probe = Split-Path $probe -Parent
    }
    return $null
}

function Get-LocAgentPayloadValue {
    param($Payload, [string]$Name)
    if ($null -eq $Payload) { return $null }
    if ($Payload -is [hashtable]) {
        if ($Payload.ContainsKey($Name)) { return $Payload[$Name] }
        return $null
    }
    $p = $Payload.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Test-LocAgentPayloadHasForbiddenScript {
    param($Payload)
    $forbidden = @('Script', 'ScriptText', 'Command', 'RawScript', 'PowerShell', 'Code')
    foreach ($name in $forbidden) {
        if ($null -ne (Get-LocAgentPayloadValue -Payload $Payload -Name $name)) { return $name }
    }
    return $null
}

function Invoke-LocAgentModuleAction {
    param($Payload, $AddLog)

    $bad = Test-LocAgentPayloadHasForbiddenScript -Payload $Payload
    if ($bad) { throw "Unstructured script field '$bad' is forbidden" }

    $transactionId = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'transactionId')
    $targetAgentId = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'targetAgentId')
    $module = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'module')
    $action = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'action')
    $riskLevel = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'riskLevel')
    $kind = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'kind')
    if (-not $kind) { $kind = [string](Get-LocAgentPayloadValue -Payload $Payload -Name 'Kind') }

    if ([string]::IsNullOrWhiteSpace($transactionId) -or [string]::IsNullOrWhiteSpace($targetAgentId) -or
        [string]::IsNullOrWhiteSpace($module) -or [string]::IsNullOrWhiteSpace($action) -or
        [string]::IsNullOrWhiteSpace($riskLevel)) {
        throw 'transactionId, targetAgentId, module, action, riskLevel required'
    }

    if ($module -notmatch '^[A-Za-z0-9._-]+$' -or $action -notmatch '^[A-Za-z0-9._-]+$') {
        throw 'Invalid module or action name'
    }
    if ($module -match '\.\.' -or $action -match '\.\.') {
        throw 'Path traversal rejected'
    }

    $modulesRoot = Get-LocAgentModulesRoot
    if (-not $modulesRoot) { throw 'modules root not found next to agent or console' }

    $kinds = @()
    if ($kind -match '^(?i)diagnostics|actions$') {
        $kinds = @($kind.ToLowerInvariant())
    }
    else {
        $kinds = @('diagnostics', 'actions')
    }

    $scriptPath = $null
    $resolvedKind = $null
    foreach ($k in $kinds) {
        $candidate = Join-Path $modulesRoot (Join-Path $module (Join-Path $k "$action.ps1"))
        $full = [System.IO.Path]::GetFullPath($candidate)
        $rootFull = [System.IO.Path]::GetFullPath($modulesRoot)
        if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Path jail violation'
        }
        if (Test-Path -LiteralPath $full) {
            $scriptPath = $full
            $resolvedKind = $k
            break
        }
    }
    if (-not $scriptPath) {
        throw ("Module script not found under modules/{0}/{{diagnostics|actions}}/{1}.ps1" -f $module, $action)
    }

    & $AddLog ("ModuleAction {0}/{1}/{2} risk={3} tx={4}" -f $module, $resolvedKind, $action, $riskLevel, $transactionId)

    $parameters = Get-LocAgentPayloadValue -Payload $Payload -Name 'parameters'
    $splat = @{}
    if ($parameters -is [hashtable]) {
        $splat = $parameters
    }
    elseif ($parameters) {
        foreach ($p in $parameters.PSObject.Properties) { $splat[$p.Name] = $p.Value }
    }

    $rawOutput = @(. $scriptPath @splat)
    $result = $rawOutput | Where-Object {
        $null -ne $_ -and ($_.PSObject.Properties.Name -contains 'Success')
    } | Select-Object -Last 1

    if ($null -eq $result) {
        return @{
            Success = $true
            Message = "Executed $module/$resolvedKind/$action"
            Data    = @{
                transactionId = $transactionId
                targetAgentId = $targetAgentId
                module        = $module
                action        = $action
                kind          = $resolvedKind
                riskLevel     = $riskLevel
                Output        = @($rawOutput)
            }
        }
    }

    return @{
        Success = [bool]$result.Success
        Message = if ($result.Message) { [string]$result.Message } else { "ModuleAction $action" }
        Data    = @{
            transactionId = $transactionId
            targetAgentId = $targetAgentId
            module        = $module
            action        = $action
            kind          = $resolvedKind
            riskLevel     = $riskLevel
            Result        = $result
        }
    }
}

function Invoke-AgentCommand {
    param(
        [Parameter(Mandatory)] [string]$CommandId,
        [Parameter(Mandatory)] [string]$Type,
        [object]$Payload
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $logs = [System.Collections.ArrayList]::new()
    $r = [ordered]@{
        Payload  = $Payload
        Success  = $false
        Message  = ""
        Data     = $null
        ExitCode = 0
        AddLog   = $null
    }
    $r.AddLog = {
        param([string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
        [void]$logs.Add($Line)
        Write-AgentLog $Line
    }

    try {
        & $r.AddLog "Executing $Type ($CommandId)"
        if ($Type -eq 'ModuleAction') {
            $out = Invoke-LocAgentModuleAction -Payload $Payload -AddLog $r.AddLog
            $r.Success = [bool]$out.Success
            $r.Message = [string]$out.Message
            $r.Data = $out.Data
            if (-not $r.Success -and $r.ExitCode -eq 0) { $r.ExitCode = 1 }
        }
        elseif ($script:LocAgentHandlers -and $script:LocAgentHandlers.ContainsKey($Type)) {
            & $script:LocAgentHandlers[$Type] $r
        }
        else {
            throw "Unknown command type: $Type"
        }
    }
    catch {
        $r.Message = $_.Exception.Message
        & $r.AddLog "ERROR: $($r.Message)"
        $r.Success = $false
        if ($r.ExitCode -eq 0) { $r.ExitCode = 1 }
    }

    $sw.Stop()
    Send-AgentResult -CommandId $CommandId -Success ([bool]$r.Success) -Message ([string]$r.Message) `
        -Data $r.Data -ExitCode ([int]$r.ExitCode) -DurationMs ([int]$sw.ElapsedMilliseconds) -LogLines @($logs)

    if ($script:AgentRestartAfterCommand) {
        Write-AgentLog "SelfUpdate complete - restarting LocalOpsAgent scheduled task"
        try {
            $psExe = (Get-Command powershell.exe).Source
            $restartCmd = 'Start-Sleep -Seconds 3; Start-ScheduledTask -TaskName ''LocalOpsAgent'''
            Start-Process -FilePath $psExe -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', $restartCmd
            ) -WindowStyle Hidden | Out-Null
        }
        catch {
            Write-AgentLog ("Failed to schedule restart: {0}" -f $_.Exception.Message) "ERROR"
        }
        exit 0
    }
}
