# start.ps1 - LocalOpsConsole launcher (hidden window by default; UI Shutdown/Restart control the server)
# Note: "hidden window" is not the same as appliance/API-only mode — use -NoBrowser / -Appliance for that.
[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$NoBrowser,
    [switch]$Appliance
)

$ErrorActionPreference = "Continue"
$Root = $PSScriptRoot
$script:LocStartShowConsole = [bool]$ShowConsole
$script:LocStartNoBrowser = [bool]$NoBrowser -or [bool]$Appliance
$script:LocStartAppliance = [bool]$Appliance

function Write-LocStartHost {
    param([string]$Message, [string]$Color = "Gray")
    if (-not $script:LocStartShowConsole) { return }
    if ($Color -and $Color -ne "Gray") {
        Write-Host $Message -ForegroundColor $Color
    }
    else {
        Write-Host $Message
    }
}

function Write-LocStartProgress {
    param(
        [ValidateRange(0, 100)]
        [int]$Percent,
        [string]$Label = "",
        [switch]$NewLine
    )
    if (-not $script:LocStartShowConsole) { return }
    $width = 24
    $filled = [math]::Round(($Percent / 100.0) * $width)
    if ($filled -gt $width) { $filled = $width }
    $bar = ("#" * $filled) + ("." * ($width - $filled))
    $line = "[{0}] {1,3}%  {2}" -f $bar, $Percent, $Label
    if ($NewLine) {
        Write-Host $line
    }
    else {
        Write-Host ("`r" + $line.PadRight(100)) -NoNewline
    }
}

function Clear-LocStartProgressLine {
    if (-not $script:LocStartShowConsole) { return }
    Write-Host ("`r" + (" " * 100) + "`r") -NoNewline
}

function Read-LocRedirectTail {
    param([string]$Path, [int]$MaxChars = 1200)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
        if ($raw.Length -le $MaxChars) { return $raw.Trim() }
        return $raw.Substring($raw.Length - $MaxChars).Trim()
    }
    catch {
        return ""
    }
}

function Test-LocListeningInLog {
    param([string]$RootPath)
    $logPath = Join-Path $RootPath ("logs\{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
    if (-not (Test-Path -LiteralPath $logPath)) { return $false }
    try {
        $tail = Get-Content -LiteralPath $logPath -Tail 40 -ErrorAction SilentlyContinue
        return [bool]($tail | Where-Object { $_ -match 'CORE \| Server \| SUCCESS \| Listening' })
    }
    catch {
        return $false
    }
}

function Save-LocServerPid {
    param([int]$ProcessId)
    $dir = Join-Path $Root "data\runtime"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $pidPath = Join-Path $dir "server.pid"
    [System.IO.File]::WriteAllText($pidPath, [string]$ProcessId, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-LocStartFailureVisible {
    param(
        [int]$Code = 1,
        [string]$Message = "",
        [string]$Detail = ""
    )
    $failFile = Join-Path $env:TEMP "LocalOpsConsole-start-fail.txt"
    $text = New-Object System.Collections.Generic.List[string]
    [void]$text.Add("LocalOpsConsole failed to start.")
    if ($Message) { [void]$text.Add($Message) }
    if ($Detail) { [void]$text.Add(""); [void]$text.Add($Detail) }
    [void]$text.Add("")
    [void]$text.Add("Press Enter to close...")
    [System.IO.File]::WriteAllText($failFile, ($text -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

    if (-not $script:LocStartShowConsole) {
        $cmd = @"
`$ErrorActionPreference='Continue'
Get-Content -LiteralPath '$failFile' -ErrorAction SilentlyContinue | Write-Host
Write-Host ''
try { [void][Console]::ReadLine() } catch { Start-Sleep -Seconds 8 }
Remove-Item -LiteralPath '$failFile' -Force -ErrorAction SilentlyContinue
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WindowStyle Normal | Out-Null
        exit $Code
    }

    Get-Content -LiteralPath $failFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }
    Remove-Item -LiteralPath $failFile -Force -ErrorAction SilentlyContinue
    try { [void][Console]::ReadLine() } catch { Start-Sleep -Seconds 8 }
    exit $Code
}

# Force Administrator - elevate hidden PowerShell (no CMD window)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-LocStartHost "Requesting Administrator elevation (UAC)..." "Yellow"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $showArg = if ($script:LocStartShowConsole) { " -ShowConsole" } else { "" }
    $noBrowserArg = if ($script:LocStartNoBrowser) { " -NoBrowser" } else { "" }
    $applianceArg = if ($script:LocStartAppliance) { " -Appliance" } else { "" }
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"$showArg$noBrowserArg$applianceArg"
    $psi.WorkingDirectory = $Root
    $psi.Verb = "runas"
    $psi.UseShellExecute = $true
    try {
        $elev = [Diagnostics.Process]::Start($psi)
        if (-not $elev) {
            Invoke-LocStartFailureVisible -Message "Elevation failed to start."
        }
        # Detach: elevated process continues with a hidden window; this (often visible bat) exits.
        exit 0
    }
    catch {
        Invoke-LocStartFailureVisible -Message "Elevation cancelled. Remediations will be restricted without Administrator." `
            -Detail "Re-run start.bat and accept the UAC prompt, or continue without admin for limited mode."
        # If user cancels, fall through only when ShowConsole and they want limited mode — plan says show error.
        # Exit after visible failure above.
    }
}

Write-LocStartProgress -Percent 5 -Label "Checking elevation..." -NewLine

$VersionFile = Join-Path $Root "VERSION"
$Version = if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw).Trim() } else { "0.0.0" }

$SettingsPath = Join-Path $Root "settings.json"
$Port = 8787
$cfg = $null
if (Test-Path $SettingsPath) {
    try {
        $cfg = Get-Content $SettingsPath -Raw | ConvertFrom-Json
        if ($cfg.port) { $Port = [int]$cfg.port }
    }
    catch { Write-Debug $_.Exception.Message }
}

$Url = "http://localhost:$Port/"
$ApiServer = Join-Path $Root "api\server.ps1"
$healthUrl = "http://localhost:{0}/api/v1/health" -f $Port

Write-LocStartHost "====================================================" "Cyan"
Write-LocStartHost " LocalOpsConsole v$Version" "Green"
Write-LocStartHost " Windows Diagnostic Platform" "Green"
Write-LocStartHost "====================================================" "Cyan"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdmin) {
    Write-LocStartHost "Elevated session. Full remediation available." "Green"
}
else {
    Write-LocStartHost "Warning: Non-elevated. Remediation actions will be restricted." "Yellow"
}

Write-LocStartProgress -Percent 15 -Label "Probing existing server..." -NewLine

    try {
        $existing = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
        if ($existing.StatusCode -eq 200) {
        Write-LocStartProgress -Percent 100 -Label "Server already running" -NewLine
        if ($script:LocStartNoBrowser) {
            Write-LocStartHost "Server already running on port $Port (no browser)." "Yellow"
        }
        else {
            Write-LocStartHost "Server already running on port $Port - opening UI." "Yellow"
            Start-Process $Url
        }
        exit 0
    }
}
catch { Write-Debug $_.Exception.Message }

$staleOwnerPid = $null
try {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($conn) {
        $staleOwnerPid = [int]$conn.OwningProcess
        Write-LocStartHost ("Port {0} is listening (PID {1}) but /api/v1/health is not healthy." -f $Port, $staleOwnerPid) "Yellow"
        if ($isAdmin -and $staleOwnerPid -gt 0) {
            Write-LocStartHost "Stopping stale listener..." "DarkYellow"
            try {
                Stop-Process -Id $staleOwnerPid -Force -ErrorAction Stop
                Start-Sleep -Seconds 1
            }
            catch {
                Invoke-LocStartFailureVisible -Message ("Could not stop stale PID {0}: {1}" -f $staleOwnerPid, $_.Exception.Message)
            }
        }
        else {
            Invoke-LocStartFailureVisible -Message ("Stale instance on port {0}. Run as Administrator or: Stop-Process -Id {1} -Force" -f $Port, $staleOwnerPid)
        }
    }
}
catch { Write-Debug $_.Exception.Message }

Write-LocStartProgress -Percent 25 -Label "Reading settings / URL ACL..." -NewLine

$bindHostCfg = "localhost"
try {
    if ($cfg -and $cfg.bindHost) { $bindHostCfg = [string]$cfg.bindHost }
}
catch { Write-Debug $_.Exception.Message }
. (Join-Path $Root "core\Settings.ps1")
$listenHosts = @(Resolve-LocHttpListenHosts -BindHost $bindHostCfg)
if ($isAdmin) {
    foreach ($lh in $listenHosts) {
        if ($lh -match '^(?i)(localhost|127\.0\.0\.1)$') { continue }
        $aclUrl = "http://${lh}:${Port}/"
        $existingAcl = netsh http show urlacl url=$aclUrl 2>$null
        if ("$existingAcl" -notmatch [regex]::Escape($aclUrl)) {
            Write-LocStartHost "Adding URL ACL $aclUrl ..." "DarkGray"
            netsh http add urlacl url=$aclUrl user=Everyone >$null 2>&1
        }
    }
}
elseif ($listenHosts | Where-Object { $_ -notmatch '^(?i)(localhost|127\.0\.0\.1)$' }) {
    Write-LocStartHost "Warning: bindHost=$bindHostCfg needs Administrator for LAN listen." "Yellow"
}

$modulesPath = Join-Path $Root "modules"
$dashboardPath = Join-Path $Root "dashboard"
$errLog = Join-Path $env:TEMP "LocalOpsConsole-server-err.log"
$outLog = Join-Path $env:TEMP "LocalOpsConsole-server-out.log"
Remove-Item $errLog, $outLog -ErrorAction SilentlyContinue

Write-LocStartProgress -Percent 40 -Label "Starting server process..." -NewLine

$argParts = @(
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    "-WindowStyle Hidden",
    "-File `"$ApiServer`"",
    "-Port $Port",
    "-ModulesPath `"$modulesPath`"",
    "-DashboardPath `"$dashboardPath`"",
    "-RootPath `"$Root`""
)
# Appliance: pass -NoStatic and -ProductMode without rewriting settings.json
if ($script:LocStartAppliance) {
    $argParts += "-NoStatic"
    $argParts += "-ProductMode"
    $argParts += "appliance"
}
$argString = $argParts -join " "

$serverProc = Start-Process -FilePath "powershell.exe" -ArgumentList $argString `
    -PassThru -WindowStyle Hidden `
    -RedirectStandardError $errLog -RedirectStandardOutput $outLog

$ready = $false
$lastStatus = $null
$lastBody = ""
$heardListening = $false
$maxAttempts = 120
for ($i = 0; $i -lt $maxAttempts; $i++) {
    Start-Sleep -Milliseconds 500
    $null = Read-LocRedirectTail -Path $outLog
    $null = Read-LocRedirectTail -Path $errLog
    if (-not $heardListening -and (Test-LocListeningInLog -RootPath $Root)) {
        $heardListening = $true
    }

    $pct = 45 + [int]((50.0 * ($i + 1)) / $maxAttempts)
    if ($pct -gt 95) { $pct = 95 }
    $label = if ($heardListening) {
        "Listener up — waiting for health... {0}s" -f [math]::Round(($i + 1) * 0.5, 1)
    }
    else {
        "Waiting for health... {0}s" -f [math]::Round(($i + 1) * 0.5, 1)
    }
    Write-LocStartProgress -Percent $pct -Label $label

    if ($serverProc.HasExited) { break }
    try {
        $h = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 8
        $lastStatus = [int]$h.StatusCode
        $lastBody = if ($h.Content) {
            $c = [string]$h.Content
            if ($c.Length -gt 240) { $c.Substring(0, 240) + "..." } else { $c }
        }
        else { "" }
        if ($h.StatusCode -eq 200) { $ready = $true; break }
    }
    catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            try { $lastStatus = [int]$ex.Response.StatusCode } catch { Write-Debug $_.Exception.Message }
        }
        if ($ex.Response) {
            try {
                $stream = $ex.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $lastBody = $reader.ReadToEnd()
                    if ($lastBody.Length -gt 240) { $lastBody = $lastBody.Substring(0, 240) + "..." }
                }
            }
            catch { Write-Debug $_.Exception.Message }
        }
        elseif ($ex.Message) {
            $lastBody = $ex.Message
        }
    }
}

Clear-LocStartProgressLine

if (-not $ready) {
    $detail = New-Object System.Collections.Generic.List[string]
    if ($heardListening) { [void]$detail.Add("Log shows Listening SUCCESS, but /api/v1/health did not return HTTP 200.") }
    if ($null -ne $lastStatus) { [void]$detail.Add(("Last health status: {0}" -f $lastStatus)) }
    if ($lastBody) { [void]$detail.Add($lastBody.Trim()) }
    $errText = Read-LocRedirectTail -Path $errLog
    if ($errText) { [void]$detail.Add("--- server error ---"); [void]$detail.Add($errText) }
    $outText = Read-LocRedirectTail -Path $outLog
    if ($outText) { [void]$detail.Add("--- server output ---"); [void]$detail.Add($outText) }
    Invoke-LocStartFailureVisible -Message "Server failed to start. Check logs\ or run api\server.ps1 directly." `
        -Detail ($detail -join [Environment]::NewLine)
}

Write-LocStartProgress -Percent 100 -Label $(if ($script:LocStartNoBrowser) { "Server ready" } else { "Opening UI..." }) -NewLine
try { Save-LocServerPid -ProcessId ([int]$serverProc.Id) } catch { Write-Debug $_.Exception.Message }
if (-not $script:LocStartNoBrowser) {
    Start-Process $Url
    Write-LocStartHost ("Interface live at: {0} (server PID {1}). Use Shutdown/Restart in the UI." -f $Url, $serverProc.Id) "Green"
}
else {
    Write-LocStartHost ("API live at: {0}api/v1/health (server PID {1}). No browser opened." -f $Url, $serverProc.Id) "Green"
}
exit 0
