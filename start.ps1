# start.ps1 - Single-click LocalOpsConsole launcher (forces elevation)
$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot

# Force Administrator - relaunch via UAC if needed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "Requesting Administrator elevation (UAC)..." -ForegroundColor Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    $psi.UseShellExecute = $true
    try {
        [Diagnostics.Process]::Start($psi) | Out-Null
        exit 0
    }
    catch {
        Write-Host "Elevation cancelled. Continuing without admin - remediations will be restricted." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}

$VersionFile = Join-Path $Root "VERSION"
$Version = if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw).Trim() } else { "0.0.0" }

$SettingsPath = Join-Path $Root "settings.json"
$Port = 8787
if (Test-Path $SettingsPath) {
    try {
        $cfg = Get-Content $SettingsPath -Raw | ConvertFrom-Json
        if ($cfg.port) { $Port = [int]$cfg.port }
    }
    catch { }
}

$Url = "http://localhost:$Port/"
$ApiServer = Join-Path $Root "api\server.ps1"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " LocalOpsConsole v$Version" -ForegroundColor Green
Write-Host " Windows Diagnostic Platform" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdmin) {
    Write-Host "Elevated session. Full remediation available." -ForegroundColor Green
}
else {
    Write-Host "Warning: Non-elevated. Remediation actions will be restricted." -ForegroundColor Yellow
}

# If an older instance is already answering, reuse it
try {
    $existing = Invoke-WebRequest -Uri ("http://localhost:{0}/api/v1/health" -f $Port) -UseBasicParsing -TimeoutSec 2
    if ($existing.StatusCode -eq 200) {
        Write-Host "Server already running on port $Port - opening UI." -ForegroundColor Yellow
        Start-Process $Url
        exit 0
    }
}
catch { }

# Ensure HTTP.sys URL ACLs for non-loopback binds (requires elevation)
$bindHostCfg = "localhost"
try {
    if ($cfg -and $cfg.bindHost) { $bindHostCfg = [string]$cfg.bindHost }
}
catch { }
. (Join-Path $Root "core\Settings.ps1")
$listenHosts = @(Resolve-LocHttpListenHosts -BindHost $bindHostCfg)
if ($isAdmin) {
    foreach ($lh in $listenHosts) {
        if ($lh -match '^(?i)(localhost|127\.0\.0\.1)$') { continue }
        $aclUrl = "http://${lh}:${Port}/"
        $existingAcl = netsh http show urlacl url=$aclUrl 2>$null
        if ("$existingAcl" -notmatch [regex]::Escape($aclUrl)) {
            Write-Host "Adding URL ACL $aclUrl ..." -ForegroundColor DarkGray
            netsh http add urlacl url=$aclUrl user=Everyone >$null 2>&1
        }
    }
}
elseif ($listenHosts | Where-Object { $_ -notmatch '^(?i)(localhost|127\.0\.0\.1)$' }) {
    Write-Host "Warning: bindHost=$bindHostCfg needs Administrator to listen on the LAN. Re-run start.bat and accept UAC." -ForegroundColor Yellow
}
$modulesPath = Join-Path $Root "modules"
$dashboardPath = Join-Path $Root "dashboard"
$errLog = Join-Path $env:TEMP "LocalOpsConsole-server-err.log"
$outLog = Join-Path $env:TEMP "LocalOpsConsole-server-out.log"
Remove-Item $errLog, $outLog -ErrorAction SilentlyContinue

# Quote every path - Start-Process ArgumentList does NOT quote spaces for you
$argString = @(
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    "-File `"$ApiServer`"",
    "-Port $Port",
    "-ModulesPath `"$modulesPath`"",
    "-DashboardPath `"$dashboardPath`"",
    "-RootPath `"$Root`""
) -join " "

$serverProc = Start-Process -FilePath "powershell.exe" -ArgumentList $argString `
    -PassThru -WindowStyle Minimized `
    -RedirectStandardError $errLog -RedirectStandardOutput $outLog

# Wait until health answers or process exits (up to ~15s)
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    if ($serverProc.HasExited) { break }
    try {
        $h = Invoke-WebRequest -Uri ("http://localhost:{0}/api/v1/health" -f $Port) -UseBasicParsing -TimeoutSec 1
        if ($h.StatusCode -eq 200) { $ready = $true; break }
    }
    catch { }
}

if (-not $ready) {
    Write-Host "Server failed to start. Check logs\ or run api\server.ps1 directly." -ForegroundColor Red
    if (Test-Path $errLog) {
        $errText = (Get-Content $errLog -Raw -ErrorAction SilentlyContinue)
        if ($errText) {
            Write-Host "--- server error ---" -ForegroundColor DarkYellow
            Write-Host $errText.Trim() -ForegroundColor DarkYellow
        }
    }
    exit 1
}

Start-Process $Url

Write-Host "Interface live at: $Url" -ForegroundColor Green
Write-Host "Server PID: $($serverProc.Id)" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop this launcher (server keeps running), or: Stop-Process -Id $($serverProc.Id)" -ForegroundColor DarkGray

try {
    Wait-Process -Id $serverProc.Id
}
catch {
    Write-Host "Launcher exiting."
}
