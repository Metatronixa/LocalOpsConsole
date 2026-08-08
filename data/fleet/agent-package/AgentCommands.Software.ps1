# AgentCommands.Software.ps1 - Software / event / offender handlers
if (-not $script:LocAgentHandlers) { $script:LocAgentHandlers = @{} }

$script:LocAgentHandlers['GetRustDeskStatus'] = {
    param($r)
    $exe = $null
    foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'RustDesk'))) {
        if (-not $root) { continue }
        $cand = Join-Path $root 'rustdesk.exe'
        if (Test-Path $cand) { $exe = $cand; break }
    }
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*' } | Select-Object -First 1
    $proc = [bool](Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue)
    $id = $null
    if ($exe) {
        foreach ($cfgPath in @(
                (Join-Path $env:APPDATA 'RustDesk\config\RustDesk2.toml'),
                (Join-Path $env:LOCALAPPDATA 'RustDesk\config\RustDesk2.toml')
            )) {
            if (-not (Test-Path $cfgPath)) { continue }
            try {
                $text = Get-Content $cfgPath -Raw -ErrorAction Stop
                if ($text -match '(?m)^\s*id\s*=\s*[''"]?(\d{6,12})') { $id = $Matches[1]; break }
            }
            catch { }
        }
    }
    $r.Data = @{
        Installed      = [bool]$exe
        ExePath        = $exe
        ProcessRunning = $proc
        ServiceName    = if ($svc) { [string]$svc.Name } else { $null }
        ServiceStatus  = if ($svc) { [string]$svc.Status } else { $null }
        Id             = $id
        Note           = 'Remote passwords are never collected.'
    }
    $r.Message = if ($exe) { "RustDesk installed" } else { "RustDesk not detected" }
    $r.Success = $true
}

$script:LocAgentHandlers['InstallRustDesk'] = {
    param($r)
    $url = if ($r.Payload -and $r.Payload.InstallerUrl) { [string]$r.Payload.InstallerUrl } else { throw "InstallerUrl required (set rustDeskInstallerUrl on console)" }
    if ($url -notmatch '^https://') { throw "InstallerUrl must be HTTPS" }
    $sha = if ($r.Payload -and $r.Payload.InstallerSha256) { [string]$r.Payload.InstallerSha256 } else { '' }
    $silent = if ($r.Payload -and $r.Payload.SilentArgs) { [string]$r.Payload.SilentArgs } else { '/S' }
    $ext = [System.IO.Path]::GetExtension(($url -split '\?')[0])
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.exe' }
    $work = Join-Path $ConfigDir "installs\rustdesk"
    if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
    try { Start-Process explorer.exe -ArgumentList $work -ErrorAction SilentlyContinue } catch { }
    $tmp = Join-Path $work ("RustDesk-install-{0}{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $ext)
    & $r.AddLog "Downloading RustDesk installer..."
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    if (-not [string]::IsNullOrWhiteSpace($sha)) {
        $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $sha.ToLowerInvariant()) { throw "SHA-256 mismatch" }
    }
    $argList = @()
    if ($silent -match '\s') { $argList = $silent.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) }
    elseif ($silent) { $argList = @($silent) }
    & $r.AddLog "Running silent install..."
    $proc = Start-Process -FilePath $tmp -ArgumentList $argList -Wait -PassThru -ErrorAction Stop
    $r.ExitCode = [int]$proc.ExitCode
    $pf = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    $installed = (Test-Path (Join-Path $pf 'RustDesk\rustdesk.exe')) -or (Test-Path (Join-Path $pf86 'RustDesk\rustdesk.exe'))
    $r.Data = @{ ExitCode = $r.ExitCode; Installed = [bool]$installed; WorkDir = $work }
    $r.Success = ($installed -or $r.ExitCode -eq 0)
    $r.Message = if ($installed) { "RustDesk installed" } else { "Installer finished (exit $r.ExitCode) - verify status" }
}

$script:LocAgentHandlers['InstallPackage'] = {
    param($r)
    $pkgId = if ($r.Payload -and $r.Payload.PackageId) { [string]$r.Payload.PackageId } else { throw "PackageId required" }
    $name = if ($r.Payload -and $r.Payload.Name) { [string]$r.Payload.Name } else { $pkgId }
    $wingetId = if ($r.Payload -and $r.Payload.WingetId) { [string]$r.Payload.WingetId } else { '' }
    $url = if ($r.Payload -and $r.Payload.Url) { [string]$r.Payload.Url } else { '' }
    $silent = if ($r.Payload -and $r.Payload.SilentArgs) { [string]$r.Payload.SilentArgs } else { '' }
    $sha = if ($r.Payload -and $r.Payload.Sha256) { [string]$r.Payload.Sha256 } else { '' }
    $fileName = if ($r.Payload -and $r.Payload.FileName) { [string]$r.Payload.FileName } else { '' }
    $localSource = $false
    if ($r.Payload -and $r.Payload.LocalSource) { $localSource = [bool]$r.Payload.LocalSource }
    elseif ($r.Payload -and $r.Payload.Source -and ([string]$r.Payload.Source).ToLowerInvariant() -eq 'local') { $localSource = $true }
    $work = Join-Path $ConfigDir "installs\$pkgId"
    if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
    try { Start-Process explorer.exe -ArgumentList $work -ErrorAction SilentlyContinue } catch { }
    & $r.AddLog "Install work dir: $work"
    $method = $null
    if ($wingetId) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($winget) {
            $method = 'winget'
            & $r.AddLog "winget install $wingetId"
            $wg = Invoke-AgentCapturedProcess -FilePath $winget.Source -ArgumentList @(
                'install', '--id', $wingetId, '-e', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
            ) -TimeoutSec 900
            foreach ($line in ($wg.StdOut -split "`r?`n")) { & $r.AddLog $line }
            foreach ($line in ($wg.StdErr -split "`r?`n")) { & $r.AddLog $line }
            $r.ExitCode = [int]$wg.ExitCode
            $r.Success = ($r.ExitCode -eq 0)
            $r.Message = "winget install $name exit $r.ExitCode"
            $r.Data = @{ PackageId = $pkgId; Name = $name; Method = $method; ExitCode = $r.ExitCode; WorkDir = $work }
        }
    }
    if (-not $method -and $localSource) {
        $method = 'local'
        & $r.AddLog "Downloading local package $pkgId via fleet API"
        $contentResp = Invoke-AgentApi -Method GET -Path ("/api/v1/fleet/packages/{0}/content" -f [uri]::EscapeDataString($pkgId)) -Signed -TimeoutSec 600
        if (-not $contentResp.Success) { throw ("Local package download failed: {0}" -f $contentResp.Message) }
        $respFile = if ($contentResp.Data.FileName) { [System.IO.Path]::GetFileName([string]$contentResp.Data.FileName) } else { '' }
        if ([string]::IsNullOrWhiteSpace($respFile)) {
            $respFile = if ($fileName) { [System.IO.Path]::GetFileName($fileName) } else { 'setup.exe' }
        }
        $tmp = Join-Path $work $respFile
        $b64 = [string]$contentResp.Data.ContentBase64
        if ([string]::IsNullOrWhiteSpace($b64)) { throw 'Package content missing ContentBase64' }
        [System.IO.File]::WriteAllBytes($tmp, [Convert]::FromBase64String($b64))
        $expected = if ($sha) { $sha.ToLowerInvariant() } elseif ($contentResp.Data.Sha256) { ([string]$contentResp.Data.Sha256).ToLowerInvariant() } else { '' }
        $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -and $actual -ne $expected) { throw "SHA-256 mismatch for local package $pkgId" }
        if ([string]::IsNullOrWhiteSpace($silent) -and $contentResp.Data.SilentArgs) {
            $silent = [string]$contentResp.Data.SilentArgs
        }
        if ([string]::IsNullOrWhiteSpace($silent)) { $silent = '/S' }
        $argList = @()
        if ($silent -match '\s') { $argList = $silent.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) }
        elseif ($silent) { $argList = @($silent) }
        & $r.AddLog ("Running local installer {0} {1}" -f $tmp, $silent)
        $proc = Start-Process -FilePath $tmp -ArgumentList $argList -Wait -PassThru -ErrorAction Stop
        $r.ExitCode = [int]$proc.ExitCode
        $r.Success = ($r.ExitCode -eq 0)
        $r.Message = "local install $name exit $r.ExitCode"
        $r.Data = @{ PackageId = $pkgId; Name = $name; Method = $method; ExitCode = $r.ExitCode; WorkDir = $work; FileName = $respFile }
    }
    if (-not $method) {
        if ([string]::IsNullOrWhiteSpace($url)) { throw "No winget, local source, or Url for package $pkgId" }
        if ($url -notmatch '^https://') { throw "Package Url must be HTTPS" }
        $method = 'url'
        $ext = [System.IO.Path]::GetExtension(($url -split '\?')[0])
        if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.exe' }
        $tmp = Join-Path $work ("install-{0}{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $ext)
        & $r.AddLog "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        if (-not [string]::IsNullOrWhiteSpace($sha)) {
            $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $sha.ToLowerInvariant()) { throw "SHA-256 mismatch" }
        }
        $argList = @()
        if ($silent -match '\s') { $argList = $silent.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) }
        elseif ($silent) { $argList = @($silent) }
        $proc = Start-Process -FilePath $tmp -ArgumentList $argList -Wait -PassThru -ErrorAction Stop
        $r.ExitCode = [int]$proc.ExitCode
        $r.Success = ($r.ExitCode -eq 0)
        $r.Message = "URL install $name exit $r.ExitCode"
        $r.Data = @{ PackageId = $pkgId; Name = $name; Method = $method; ExitCode = $r.ExitCode; WorkDir = $work }
    }
}

$script:LocAgentHandlers['GetEventLogTail'] = {
    param($r)
    $logName = 'System'
    if ($r.Payload -and $r.Payload.LogName) { $logName = [string]$r.Payload.LogName }
    $allowed = @('System', 'Application', 'Security')
    if ($allowed -notcontains $logName) { $logName = 'System' }
    $count = 40
    if ($r.Payload -and $r.Payload.Count) { $count = [Math]::Min(100, [Math]::Max(5, [int]$r.Payload.Count)) }
    $entries = @(Get-WinEvent -LogName $logName -MaxEvents $count -ErrorAction SilentlyContinue | ForEach-Object {
            $msg = [string]$_.Message
            if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
            @{
                TimeCreated = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                Id          = $_.Id
                Level       = [string]$_.LevelDisplayName
                Provider    = [string]$_.ProviderName
                Message     = $msg
            }
        })
    $r.Data = @{ LogName = $logName; Count = $entries.Count; Entries = @($entries) }
    $r.Message = ('Event log {0} ({1} entries)' -f $logName, $entries.Count)
    $r.Success = $true
}

$script:LocAgentHandlers['GetResourceOffenders'] = {
    param($r)
    $topN = 8
    if ($r.Payload -and $r.Payload.Top) { $topN = [Math]::Min(20, [Math]::Max(3, [int]$r.Payload.Top)) }
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First $topN |
        ForEach-Object {
            $svcMatch = $null
            try {
                $svc = Get-CimInstance Win32_Service -Filter ("ProcessId={0}" -f $_.Id) -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($svc) { $svcMatch = @{ Name = [string]$svc.Name; DisplayName = [string]$svc.DisplayName; State = [string]$svc.State } }
            }
            catch { }
            @{
                Name           = [string]$_.Name
                Id             = $_.Id
                CPU            = $_.CPU
                WorkingSetMB   = [math]::Round($_.WorkingSet64 / 1MB, 1)
                RelatedService = $svcMatch
            }
        })
    $related = $null
    if ($procs.Count -gt 0 -and $procs[0].RelatedService) { $related = $procs[0].RelatedService }
    $summary = if ($procs.Count -gt 0) {
        $svcBit = if ($related) { (' / {0}' -f $related.Name) } else { '' }
        '{0} ({1} MB){2}' -f $procs[0].Name, $procs[0].WorkingSetMB, $svcBit
    } else { 'No processes' }
    $r.Data = @{
        TopProcesses   = @($procs)
        RelatedService = $related
        Summary        = $summary
        CapturedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $r.Message = "Offenders: $summary"
    $r.Success = $true
}
