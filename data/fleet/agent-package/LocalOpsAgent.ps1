#Requires -Version 5.1
# LocalOpsAgent.ps1 - Outbound fleet agent host loop (v2.3.0)

$ErrorActionPreference = "Continue"
$AgentVersion = "2.3.0"
$ConfigDir = "C:\ProgramData\LocalOpsAgent"
$ConfigPath = Join-Path $ConfigDir "config.json"
$LogDir = Join-Path $ConfigDir "logs"
if (-not $ConfigPath -or -not $LogDir) { throw "Agent config paths required" }
$HeartbeatIntervalSec = 30
$PollIntervalSec = 3
$script:AgentRestartAfterCommand = $false
$script:LocAgentHandlers = @{}

$script:LocAgentDir = $PSScriptRoot
if (-not $script:LocAgentDir) {
    $script:LocAgentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$agentLibs = @(
    'AgentCommon.ps1',
    'CapabilityDetector.ps1',
    'EnvironmentProfileDetector.ps1',
    'AgentTelemetry.ps1',
    'SecurityEventForwarder.ps1',
    'CommandDispatcher.ps1',
    'AgentCommands.Core.ps1',
    'AgentCommands.Local.ps1',
    'AgentCommands.Net.ps1',
    'AgentCommands.Software.ps1',
    'AgentCommands.Maint.ps1',
    'AgentCommands.Security.ps1'
)
foreach ($lib in $agentLibs) {
    $path = Join-Path $script:LocAgentDir $lib
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing agent library: $path"
    }
    . $path
}

# --- Main ---
Write-AgentLog "LocalOps Agent $AgentVersion starting"

$script:AgentConfig = Get-AgentConfig
if (-not $script:AgentConfig -or -not $script:AgentConfig.AgentId) {
    $enrollToken = $env:LOCALOPS_ENROLL_TOKEN
    $serverUrl = $env:LOCALOPS_SERVER_URL
    if (-not $enrollToken -and $script:AgentConfig -and $script:AgentConfig.EnrollToken) {
        $enrollToken = [string]$script:AgentConfig.EnrollToken
    }
    if (-not $serverUrl -and $script:AgentConfig -and $script:AgentConfig.ServerUrl) {
        $serverUrl = [string]$script:AgentConfig.ServerUrl
    }
    if (-not $enrollToken -or -not $serverUrl) {
        Write-AgentLog "No AgentId and missing EnrollToken/ServerUrl - exiting" "ERROR"
        exit 1
    }
    try {
        Invoke-AgentEnroll -ServerUrl $serverUrl -EnrollToken $enrollToken
    }
    catch {
        Write-AgentLog "Enrollment failed: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

$lastHeartbeat = [datetime]::MinValue

while ($true) {
    $now = Get-Date
    if (($now - $lastHeartbeat).TotalSeconds -ge $HeartbeatIntervalSec) {
        Send-AgentHeartbeat
        if (Get-Command Pulse-LocThreatSecurityForwarder -ErrorAction SilentlyContinue) {
            Pulse-LocThreatSecurityForwarder -IntervalSec $HeartbeatIntervalSec
        }
        $lastHeartbeat = $now
    }

    $cmds = Get-AgentPendingCommands
    foreach ($cmd in $cmds) {
        $cid = if ($cmd.Id) { [string]$cmd.Id } else { [string]$cmd.id }
        $ctype = if ($cmd.Type) { [string]$cmd.Type } else { [string]$cmd.type }
        Invoke-AgentCommand -CommandId $cid -Type $ctype -Payload $cmd.Payload
    }

    Start-Sleep -Seconds $PollIntervalSec
}

