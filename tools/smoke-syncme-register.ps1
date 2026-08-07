#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke-test SyncMe register endpoint on LocalOps Console.
#>
param(
    [string]$BaseUrl = "http://127.0.0.1:8787/api/v1",
    [string]$InstallPath = ""
)

$ErrorActionPreference = "Stop"
$base = $BaseUrl.TrimEnd("/")

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $sibling = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\SyncMe"))
    if (Test-Path (Join-Path $sibling "SyncMe-Host.ps1")) {
        $InstallPath = $sibling
    }
    else {
        $InstallPath = "C:\SyncMe"
    }
}

Write-Host "POST $base/syncme/register  installPath=$InstallPath"
$body = @{
    installPath = $InstallPath
    version     = "smoke"
    hostname    = $env:COMPUTERNAME
    siteId      = "smoke-test"
    consoleUrl  = "http://127.0.0.1:17845/"
    listening   = $false
    success     = $true
    summary     = "smoke-syncme-register"
    setId       = "smoke"
    setName     = "Smoke"
    endedUtc    = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Compress

try {
    $reg = Invoke-RestMethod -Uri "$base/syncme/register" -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec 15
    Write-Host ("Register Success={0} Message={1}" -f $reg.Success, $reg.Message)
}
catch {
    Write-Host "Register FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$status = Invoke-RestMethod -Uri "$base/syncme/diagnostics/GetStatus" -Method Get -TimeoutSec 15
Write-Host ("GetStatus Success={0} Path={1} LastSeen={2}" -f $status.Success, $status.Data.Path, $status.Data.LastSeenUtc)
if (-not $status.Success -or -not $status.Data.Path) {
    Write-Host "GetStatus did not return a Path - check registration." -ForegroundColor Yellow
    exit 1
}
Write-Host "OK" -ForegroundColor Green
