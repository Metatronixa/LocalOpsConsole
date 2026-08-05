# RustDesk detection and control helpers - never expose passwords

function Get-RustDeskInstallSettings {
    $settings = Get-LocSettings
    $url = ''
    $sha = ''
    $silent = ''
    if ($settings.PSObject.Properties['rustDeskInstallerUrl']) { $url = [string]$settings.rustDeskInstallerUrl }
    if ($settings.PSObject.Properties['rustDeskInstallerSha256']) { $sha = [string]$settings.rustDeskInstallerSha256 }
    if ($settings.PSObject.Properties['rustDeskSilentArgs']) { $silent = [string]$settings.rustDeskSilentArgs }
    if ([string]::IsNullOrWhiteSpace($silent)) { $silent = '/S' }
    return [PSCustomObject]@{
        InstallerUrl   = $url.Trim()
        InstallerSha256 = $sha.Trim()
        SilentArgs     = $silent.Trim()
    }
}

function Get-RustDeskCandidatePaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    $roots = @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        (Join-Path $env:LOCALAPPDATA 'RustDesk'),
        (Join-Path $env:APPDATA 'RustDesk')
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $exe = Join-Path $root 'rustdesk.exe'
        if (Test-Path $exe) { $paths.Add([System.IO.Path]::GetFullPath($exe)) }
    }

    try {
        $appPath = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\rustdesk.exe' -ErrorAction SilentlyContinue
        if ($appPath -and $appPath.'(default)' -and (Test-Path $appPath.'(default)')) {
            $paths.Add([System.IO.Path]::GetFullPath([string]$appPath.'(default)'))
        }
    }
    catch { }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallRoots) {
        try {
            Get-ItemProperty $key -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.DisplayName -like '*RustDesk*') {
                    if ($_.InstallLocation) {
                        $exe = Join-Path $_.InstallLocation 'rustdesk.exe'
                        if (Test-Path $exe) { $paths.Add([System.IO.Path]::GetFullPath($exe)) }
                    }
                    if ($_.DisplayIcon -and $_.DisplayIcon -match 'rustdesk\.exe') {
                        $icon = ($_.DisplayIcon -replace ',.*$', '').Trim('"')
                        if (Test-Path $icon) { $paths.Add([System.IO.Path]::GetFullPath($icon)) }
                    }
                }
            }
        }
        catch { }
    }

    return @($paths | Select-Object -Unique)
}

function Get-RustDeskExePath {
    $candidates = Get-RustDeskCandidatePaths
    if ($candidates.Count -gt 0) { return $candidates[0] }
    return $null
}

function Get-RustDeskVersion {
    param([string]$ExePath)
    if (-not $ExePath -or -not (Test-Path $ExePath)) { return $null }
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath)
        if ($vi.ProductVersion) { return [string]$vi.ProductVersion.Trim() }
        if ($vi.FileVersion) { return [string]$vi.FileVersion.Trim() }
    }
    catch { }
    return $null
}

function Get-RustDeskUninstallInfo {
    $found = $null
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        try {
            Get-ItemProperty $key -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.DisplayName -like '*RustDesk*' -and -not $found) {
                    $found = [PSCustomObject]@{
                        DisplayName    = [string]$_.DisplayName
                        DisplayVersion = if ($_.DisplayVersion) { [string]$_.DisplayVersion } else { $null }
                        InstallLocation = if ($_.InstallLocation) { [string]$_.InstallLocation.Trim('"', ' ') } else { $null }
                    }
                }
            }
        }
        catch { }
    }
    return $found
}

function Get-RustDeskServiceInfo {
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*'
    } | Select-Object -First 1

    if (-not $svc) {
        return [PSCustomObject]@{
            Found  = $false
            Name   = $null
            Status = $null
            StartType = $null
        }
    }

    return [PSCustomObject]@{
        Found     = $true
        Name      = [string]$svc.Name
        Status    = [string]$svc.Status
        StartType = [string]$svc.StartType
    }
}

function Test-RustDeskProcessRunning {
    $proc = Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue
    return [bool]$proc
}

function Get-RustDeskConfigPaths {
    $dirs = @(
        (Join-Path $env:APPDATA 'RustDesk\config'),
        (Join-Path $env:LOCALAPPDATA 'RustDesk\config')
    ) | Select-Object -Unique

    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($name in @('RustDesk2.toml', 'RustDesk.toml', 'config.toml')) {
            $p = Join-Path $dir $name
            if (Test-Path $p) { $files.Add($p) }
        }
    }
    return @($files)
}

function Read-RustDeskIdFromConfig {
    param([string[]]$ConfigPaths)

    foreach ($path in $ConfigPaths) {
        try {
            $text = Get-Content -Path $path -Raw -ErrorAction Stop
            if ($text -match "(?m)^\s*id\s*=\s*['`"]([^'`"]+)['`"]") {
                return $Matches[1].Trim()
            }
            if ($text -match "(?m)^\s*id\s*=\s*(\d{6,12})\s*$") {
                return $Matches[1].Trim()
            }
        }
        catch { }
    }
    return $null
}

function Get-RustDeskIdFromCli {
    param(
        [string]$ExePath,
        [int]$TimeoutSeconds = 8
    )

    if (-not $ExePath -or -not (Test-Path $ExePath)) { return $null }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExePath
    $psi.Arguments = '--get-id'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        [void]$proc.Start()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch { }
            return $null
        }
        $out = $proc.StandardOutput.ReadToEnd().Trim()
        if ($out -match '\d{6,12}') { return $Matches[0] }
    }
    catch { }
    finally {
        if ($proc -and -not $proc.HasExited) {
            try { $proc.Kill() } catch { }
        }
        if ($proc) { $proc.Dispose() }
    }
    return $null
}

function Get-RustDeskClientId {
    param([string]$ExePath)

    $configPaths = Get-RustDeskConfigPaths
    $id = Read-RustDeskIdFromConfig -ConfigPaths $configPaths
    if ($id) { return $id }

    if (-not $ExePath) { $ExePath = Get-RustDeskExePath }
    return Get-RustDeskIdFromCli -ExePath $ExePath
}

function Get-RustDeskStatusSnapshot {
    $exe = Get-RustDeskExePath
    $uninstall = Get-RustDeskUninstallInfo
    $version = Get-RustDeskVersion -ExePath $exe
    if (-not $version -and $uninstall -and $uninstall.DisplayVersion) {
        $version = $uninstall.DisplayVersion
    }

    $svc = Get-RustDeskServiceInfo
    $installSettings = Get-RustDeskInstallSettings
    $id = $null
    if ($exe) {
        $id = Get-RustDeskClientId -ExePath $exe
    }

    return [PSCustomObject]@{
        Installed              = [bool]$exe
        Version                = $version
        InstallPath            = if ($exe) { [System.IO.Path]::GetDirectoryName($exe) } else { $null }
        ExePath                = $exe
        ProcessRunning         = Test-RustDeskProcessRunning
        ServiceFound           = $svc.Found
        ServiceName            = $svc.Name
        ServiceStatus          = $svc.Status
        ServiceStartType       = $svc.StartType
        Id                     = $id
        InstallerUrlConfigured = -not [string]::IsNullOrWhiteSpace($installSettings.InstallerUrl)
        UninstallDisplayName   = if ($uninstall) { $uninstall.DisplayName } else { $null }
        Note                   = 'Remote passwords are never collected or displayed.'
    }
}
