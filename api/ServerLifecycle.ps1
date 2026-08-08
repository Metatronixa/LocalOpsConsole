# api/ServerLifecycle.ps1 - shutdown + scheduled relaunch helpers (dot-sourced from server.ps1)

function Request-LocShutdown {
    $script:LocShutdownRequested = $true
    try {
        if ($script:LocHttpListener -and $script:LocHttpListener.IsListening) {
            $script:LocHttpListener.Stop()
        }
    }
    catch { Write-Debug $_.Exception.Message }
}

function Request-LocServerRelaunch {
    # Schedule hidden api/server.ps1 after port frees. Caller should then Request-LocShutdown.
    $root = if ($script:LocRootPath) { [string]$script:LocRootPath } else { Get-LocRoot }
    $port = if ($script:LocServerPort -gt 0) { [int]$script:LocServerPort } else { 8787 }
    $modulesPath = if ($script:LocModulesPath) { [string]$script:LocModulesPath } else { Join-Path $root "modules" }
    $dashboardPath = if ($script:LocDashboardPath) { [string]$script:LocDashboardPath } else { Join-Path $root "dashboard" }
    $noStaticArg = if ($script:LocNoStatic) { " -NoStatic" } else { "" }
    $productModeArg = ""
    if (Get-Command Get-LocLicenseStatus -ErrorAction SilentlyContinue) {
        $pm = [string](Get-LocLicenseStatus).ProductMode
        if ($pm -eq "appliance") { $productModeArg = " -ProductMode appliance" }
    }
    $serverPs1 = Join-Path $root "api\server.ps1"
    if (-not (Test-Path -LiteralPath $serverPs1)) {
        throw "api/server.ps1 not found under $root"
    }

    $cmd = @"
`$ErrorActionPreference = 'Continue'
`$port = $port
`$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt `$deadline) {
    `$busy = `$false
    try {
        `$busy = [bool](Get-NetTCPConnection -LocalPort `$port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
    } catch { `$busy = `$false }
    if (-not `$busy) { break }
    Start-Sleep -Milliseconds 400
}
`$arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$serverPs1`" -Port $port -ModulesPath `"$modulesPath`" -DashboardPath `"$dashboardPath`" -RootPath `"$root`"$noStaticArg$productModeArg'
`$psi = New-Object System.Diagnostics.ProcessStartInfo
`$psi.FileName = 'powershell.exe'
`$psi.Arguments = `$arg
`$psi.WorkingDirectory = '$root'
`$psi.UseShellExecute = `$true
`$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
[void][Diagnostics.Process]::Start(`$psi)
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded" -WindowStyle Hidden | Out-Null
}
