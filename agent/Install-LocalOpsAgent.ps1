#Requires -RunAsAdministrator
# Install-LocalOpsAgent.ps1 - Install LocalOps fleet agent as a scheduled task
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ServerUrl,
    [Parameter(Mandatory)]
    [string]$EnrollToken
)

$ErrorActionPreference = "Stop"
$InstallDir = "C:\Program Files\LocalOpsAgent"
$ConfigDir = "C:\ProgramData\LocalOpsAgent"
$LogDir = Join-Path $ConfigDir "logs"
$TaskName = "LocalOpsAgent"
$AgentVersion = "2.3.0"

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

Write-Host "Installing LocalOps Agent $AgentVersion..." -ForegroundColor Cyan

foreach ($d in @($InstallDir, $ConfigDir, $LogDir)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$runtime = @(
    'LocalOpsAgent.ps1', 'AgentCommon.ps1', 'CapabilityDetector.ps1', 'AgentTelemetry.ps1',
    'CommandDispatcher.ps1', 'AgentCommands.Core.ps1', 'AgentCommands.Local.ps1',
    'AgentCommands.Net.ps1', 'AgentCommands.Software.ps1', 'AgentCommands.Maint.ps1',
    'AgentCommands.Security.ps1'
)
foreach ($name in $runtime) {
    $src = Join-Path $scriptRoot $name
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing agent file required for install: $name"
    }
    Copy-Item -Path $src -Destination (Join-Path $InstallDir $name) -Force
}

$baseUrl = $ServerUrl.TrimEnd("/")
$config = [ordered]@{
    ServerUrl    = $baseUrl
    EnrollToken  = $EnrollToken
    AgentId      = ""
    AgentSecret  = ""
    InstalledAt  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    AgentVersion = $AgentVersion
}
($config | ConvertTo-Json -Depth 5) | Set-Content (Join-Path $ConfigDir "config.json") -Encoding UTF8

$psExe = (Get-Command powershell.exe).Source
$agentScript = Join-Path $InstallDir "LocalOpsAgent.ps1"
$action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentScript`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "LocalOpsConsole fleet agent" | Out-Null

Start-ScheduledTask -TaskName $TaskName
Write-Host "Agent installed. Task '$TaskName' started." -ForegroundColor Green
Write-Host "Logs: $LogDir" -ForegroundColor Gray
Write-Host "Config: $(Join-Path $ConfigDir 'config.json')" -ForegroundColor Gray
