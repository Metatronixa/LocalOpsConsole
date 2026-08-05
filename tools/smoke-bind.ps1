# tools/smoke-bind.ps1 - Offline + optional live bind/enroll checks (no release without this)
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$BaseUrl = "http://localhost:8787/api/v1",
    [string]$LanUrl = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $Root "core\Settings.ps1")

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

Write-Host "Bind host resolution tests" -ForegroundColor Cyan

$r1 = @(Resolve-LocHttpListenHosts -BindHost "localhost")
Assert-True "localhost -> localhost" (($r1.Count -eq 1) -and ($r1[0] -eq "localhost"))

$r2 = @(Resolve-LocHttpListenHosts -BindHost "127.0.0.1")
Assert-True "127.0.0.1 -> localhost" (($r2.Count -eq 1) -and ($r2[0] -eq "localhost"))

$r3 = @(Resolve-LocHttpListenHosts -BindHost "0.0.0.0")
Assert-True "0.0.0.0 -> +" (($r3.Count -eq 1) -and ($r3[0] -eq "+"))

$r4 = @(Resolve-LocHttpListenHosts -BindHost "+")
Assert-True "+ -> +" (($r4.Count -eq 1) -and ($r4[0] -eq "+"))

$r5 = @(Resolve-LocHttpListenHosts -BindHost "172.23.101.98")
Assert-True "LAN IP includes itself" ($r5 -contains "172.23.101.98")
Assert-True "LAN IP also includes localhost (UI must not break)" ($r5 -contains "localhost")
Assert-True "LAN IP has exactly 2 prefixes" ($r5.Count -eq 2)

if ($Live) {
    Write-Host ""
    Write-Host "Live API tests against $BaseUrl" -ForegroundColor Cyan
    try {
        $health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 5
        Assert-True "health" ([bool]$health.Success)
    }
    catch {
        Assert-True "health" $false $_.Exception.Message
    }

    try {
        $tok = Invoke-RestMethod -Uri "$BaseUrl/fleet/enroll-token" -TimeoutSec 5
        Assert-True "enroll-token" ([bool]$tok.Success)
        $token = [string]$tok.Data.Token
        $url = [string]$tok.Data.SuggestedUrl
        if ($tok.Success -and $tok.Data.BindMismatch) {
            Write-Host "WARN  BindMismatch: $($tok.Data.BindWarning)" -ForegroundColor Yellow
            Assert-True "detects bindHost/fleetPublicUrl mismatch" (-not [string]::IsNullOrWhiteSpace([string]$tok.Data.BindWarning))
            Write-Host "SKIP  enroll (fix bindHost before remote enroll)" -ForegroundColor DarkGray
        }
        elseif ($token -and $url) {
            $body = @{ Token = $token; ComputerName = "SMOKE-BIND-PC"; AgentVersion = "2.0.0" } | ConvertTo-Json -Compress
            $enrollUri = "$($url.TrimEnd('/'))/api/v1/fleet/enroll"
            try {
                $en = Invoke-RestMethod -Uri $enrollUri -Method POST -Body $body -ContentType "application/json" -TimeoutSec 15
                Assert-True "enroll via SuggestedUrl ($url)" ([bool]$en.Success) ([string]$en.Message)
            }
            catch {
                Assert-True "enroll via SuggestedUrl ($url)" $false $_.Exception.Message
            }
        }
        else {
            Assert-True "enroll skipped (empty token)" $false "Generate an enroll token in Computers first"
        }
    }
    catch {
        Assert-True "enroll-token" $false $_.Exception.Message
    }

    if ($LanUrl) {
        $lanHealth = "$($LanUrl.TrimEnd('/'))/api/v1/health"
        try {
            $lh = Invoke-RestMethod -Uri $lanHealth -TimeoutSec 5
            Assert-True "LAN health $LanUrl" ([bool]$lh.Success)
        }
        catch {
            Assert-True "LAN health $LanUrl" $false $_.Exception.Message
        }
    }
}

Write-Host ""
$color = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host ("Result: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $color
if ($script:fail -gt 0) { exit 1 }
exit 0
