# AgentCommands.Maint.ps1 - Maintenance and self-update handlers
if (-not $script:LocAgentHandlers) { $script:LocAgentHandlers = @{} }

$script:LocAgentHandlers['SfcScannow'] = {
    param($r)
    & $r.AddLog "Starting sfc /scannow (may take a long time)..."
    $sfc = Invoke-AgentCapturedProcess -FilePath "$env:SystemRoot\System32\sfc.exe" -ArgumentList @('/scannow')
    foreach ($line in ($sfc.StdOut -split "`r?`n")) { & $r.AddLog $line }
    foreach ($line in ($sfc.StdErr -split "`r?`n")) { & $r.AddLog $line }
    $r.ExitCode = [int]$sfc.ExitCode
    $r.Success = ($r.ExitCode -eq 0)
    $r.Message = "sfc /scannow finished (exit $r.ExitCode)"
    $r.Data = @{ ExitCode = $r.ExitCode }
}

$script:LocAgentHandlers['SelfUpdate'] = {
    param($r)
    $force = $false
    if ($r.Payload -and $r.Payload.Force) { $force = [bool]$r.Payload.Force }

    & $r.AddLog "Fetching agent package manifest..."
    $manResp = Invoke-AgentApi -Method GET -Path "/api/v1/fleet/agent-package/manifest" -Signed -TimeoutSec 30
    if (-not $manResp.Success) { throw ("Manifest failed: {0}" -f $manResp.Message) }
    $pkgVer = [string]$manResp.Data.Version
    $pkgSha = ([string]$manResp.Data.Sha256).ToLowerInvariant()
    & $r.AddLog ("Package version {0} sha={1}" -f $pkgVer, $pkgSha)

    if (-not $force -and $pkgVer -eq $AgentVersion) {
        $r.Message = "Already on agent $AgentVersion"
        $r.Data = @{ Version = $AgentVersion; Updated = $false }
        $r.Success = $true
    }
    else {
        & $r.AddLog "Downloading agent package content..."
        $contentResp = Invoke-AgentApi -Method GET -Path "/api/v1/fleet/agent-package/content" -Signed -TimeoutSec 120
        if (-not $contentResp.Success) { throw ("Content failed: {0}" -f $contentResp.Message) }
        $respSha = ([string]$contentResp.Data.Sha256).ToLowerInvariant()

        $updatesDir = Join-Path $ConfigDir "updates"
        if (-not (Test-Path $updatesDir)) { New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null }
        $stageDir = Join-Path $updatesDir ("pkg-{0}" -f $pkgVer)
        if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

        $files = @()
        if ($contentResp.Data.Files) { $files = @($contentResp.Data.Files) }
        if ($files.Count -gt 0) {
            foreach ($f in $files) {
                $name = [System.IO.Path]::GetFileName([string]$f.FileName)
                if ([string]::IsNullOrWhiteSpace($name) -or $name -match '\.\.') { throw "Invalid package file name" }
                $destTmp = Join-Path $stageDir $name
                if ($f.ContentBase64) {
                    [System.IO.File]::WriteAllBytes($destTmp, [Convert]::FromBase64String([string]$f.ContentBase64))
                }
                else {
                    throw ("Missing ContentBase64 for {0}" -f $name)
                }
                $actual = (Get-FileHash -Path $destTmp -Algorithm SHA256).Hash.ToLowerInvariant()
                $expect = if ($f.Sha256) { ([string]$f.Sha256).ToLowerInvariant() } else { '' }
                if ($expect -and $actual -ne $expect) { throw ("SHA-256 mismatch for {0}" -f $name) }
            }
        }
        else {
            $tmpFile = Join-Path $stageDir 'LocalOpsAgent.ps1'
            if ($contentResp.Data.ContentBase64) {
                [System.IO.File]::WriteAllBytes($tmpFile, [Convert]::FromBase64String([string]$contentResp.Data.ContentBase64))
            }
            else {
                $content = [string]$contentResp.Data.Content
                if ([string]::IsNullOrWhiteSpace($content)) { throw "Empty agent package content" }
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($tmpFile, $content, $utf8NoBom)
            }
            $actualSha = (Get-FileHash -Path $tmpFile -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualSha -ne $pkgSha -and $actualSha -ne $respSha) {
                throw ("SHA-256 mismatch. expected={0} actual={1}" -f $pkgSha, $actualSha)
            }
        }

        $primary = Join-Path $stageDir 'LocalOpsAgent.ps1'
        if (-not (Test-Path $primary)) { throw 'Package missing LocalOpsAgent.ps1' }
        $actualSha = (Get-FileHash -Path $primary -Algorithm SHA256).Hash.ToLowerInvariant()

        $installDir = "C:\Program Files\LocalOpsAgent"
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
        Get-ChildItem -Path $stageDir -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $installDir $_.Name) -Force
            & $r.AddLog ("Installed {0}" -f $_.Name)
        }

        $cfg = Get-AgentConfig
        if (-not $cfg) { $cfg = [ordered]@{} }
        if ($cfg -is [PSCustomObject]) {
            $cfg | Add-Member -NotePropertyName AgentVersion -NotePropertyValue $pkgVer -Force
        }
        else {
            $cfg.AgentVersion = $pkgVer
        }
        Save-AgentConfig -Config $cfg
        $script:AgentConfig = $cfg

        $r.Message = "Updated agent to $pkgVer; restarting task"
        $r.Data = @{
            PreviousVersion = $AgentVersion
            Version         = $pkgVer
            Sha256          = $actualSha
            Updated         = $true
            RestartPending  = $true
            Files           = @(Get-ChildItem $stageDir -File | ForEach-Object Name)
        }
        $r.Success = $true
        $script:AgentRestartAfterCommand = $true
    }
}

$script:LocAgentHandlers['ChkdskScan'] = {
    param($r)
    $drive = "C:"
    if ($r.Payload -and $r.Payload.Drive) { $drive = ([string]$r.Payload.Drive).TrimEnd('\') }
    if ($drive -notmatch '^[A-Za-z]:$') { $drive = "C:" }
    & $r.AddLog "Running read-only chkdsk $drive..."
    $chk = Invoke-AgentCapturedProcess -FilePath "$env:SystemRoot\System32\chkdsk.exe" -ArgumentList @($drive) -TimeoutSec 600
    foreach ($line in ($chk.StdOut -split "`r?`n")) { & $r.AddLog $line }
    foreach ($line in ($chk.StdErr -split "`r?`n")) { & $r.AddLog $line }
    $r.ExitCode = [int]$chk.ExitCode
    $r.Success = ($r.ExitCode -eq 0)
    $r.Message = "chkdsk $drive finished (exit $r.ExitCode)"
    $r.Data = @{ Drive = $drive; ExitCode = $r.ExitCode }
}

$script:LocAgentHandlers['ChkdskScheduleFix'] = {
    param($r)
    $drive = "C:"
    if ($r.Payload -and $r.Payload.Drive) { $drive = ([string]$r.Payload.Drive).TrimEnd('\') }
    if ($drive -notmatch '^[A-Za-z]:$') { $drive = "C:" }
    & $r.AddLog "Scheduling chkdsk $drive /F (may require reboot; no auto-reboot)..."
    $psiArgs = "/c echo Y| chkdsk $drive /F"
    $chk = Invoke-AgentCapturedProcess -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @($psiArgs) -TimeoutSec 120
    foreach ($line in ($chk.StdOut -split "`r?`n")) { & $r.AddLog $line }
    foreach ($line in ($chk.StdErr -split "`r?`n")) { & $r.AddLog $line }
    $r.ExitCode = [int]$chk.ExitCode
    $outAll = "$($chk.StdOut)`n$($chk.StdErr)"
    $scheduled = ($outAll -match '(?i)schedule|next time the system restarts|would you like to schedule')
    $r.Success = ($r.ExitCode -eq 0 -or $scheduled)
    $r.Message = if ($scheduled) {
        "CHKDSK /F scheduled for $drive on next restart (reboot not triggered)"
    } else {
        "chkdsk $drive /F finished (exit $r.ExitCode)"
    }
    $r.Data = @{ Drive = $drive; ExitCode = $r.ExitCode; Scheduled = [bool]$scheduled }
}
