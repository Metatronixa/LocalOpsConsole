try {
    $cfg = Get-RustDeskInstallSettings
    if ([string]::IsNullOrWhiteSpace($cfg.InstallerUrl)) {
        return New-ApiResult -Success $false -Message "rustDeskInstallerUrl is not set in settings.json. Add a direct HTTPS download URL for the RustDesk installer."
    }

    if ($cfg.InstallerUrl -notmatch '^https://') {
        return New-ApiResult -Success $false -Message "rustDeskInstallerUrl must be an HTTPS URL."
    }

    $ext = [System.IO.Path]::GetExtension(($cfg.InstallerUrl -split '\?')[0])
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.exe' }
    $tmp = Join-Path $env:TEMP ("RustDesk-install-{0}{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $ext)

    Write-LocLog -Module 'remotesupport' -Action 'InstallRustDesk' -Level 'INFO' -Message "Downloading installer"
    Invoke-WebRequest -Uri $cfg.InstallerUrl -OutFile $tmp -UseBasicParsing

    if (-not [string]::IsNullOrWhiteSpace($cfg.InstallerSha256)) {
        $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        $expected = $cfg.InstallerSha256.ToLowerInvariant()
        if ($actual -ne $expected) {
            Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
            return New-ApiResult -Success $false -Message "SHA-256 mismatch. Expected $expected, got $actual."
        }
    }

    $argList = @()
    if ($cfg.SilentArgs -match '\s') {
        $argList = $cfg.SilentArgs.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    }
    elseif ($cfg.SilentArgs) {
        $argList = @($cfg.SilentArgs)
    }

    Write-LocLog -Module 'remotesupport' -Action 'InstallRustDesk' -Level 'INFO' -Message "Running silent install"
    $proc = Start-Process -FilePath $tmp -ArgumentList $argList -Wait -PassThru -ErrorAction Stop

    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2
    $status = Get-RustDeskStatusSnapshot

    if (-not $status.Installed -and $proc.ExitCode -ne 0) {
        return New-ApiResult -Success $false -Message ("Installer exited with code {0}. RustDesk was not detected after install." -f $proc.ExitCode) -Data $status
    }

    return New-ApiResult -Success $true -Message $(if ($status.Installed) { 'RustDesk installed successfully' } else { 'Installer finished - verify RustDesk status' }) -Data $status
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
