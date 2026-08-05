#Requires -RunAsAdministrator
# Uninstall-LocalOpsAgent.ps1 - Remove LocalOps fleet agent
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = "C:\Program Files\LocalOpsAgent"
$ConfigDir = "C:\ProgramData\LocalOpsAgent"
$TaskName = "LocalOpsAgent"

Write-Host "Uninstalling LocalOps Agent..." -ForegroundColor Cyan

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}

# Keep logs/config by default; remove config if you want a clean uninstall
if (Test-Path (Join-Path $ConfigDir "config.json")) {
    Remove-Item (Join-Path $ConfigDir "config.json") -Force
}

Write-Host "LocalOps Agent uninstalled (logs preserved under $ConfigDir\logs)." -ForegroundColor Green
