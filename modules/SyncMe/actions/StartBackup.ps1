try {
    $path = Get-SyncMePath
    if (-not $path) {
        return New-ApiResult -Success $false -Message "SyncMe path not found. Let SyncMe auto-register on this PC, or set syncMePath in settings.json."
    }
    $backup = Join-Path $path "SyncMe-Backup.ps1"
    if (-not (Test-Path $backup)) {
        return New-ApiResult -Success $false -Message "SyncMe-Backup.ps1 not found in $path"
    }

    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$backup`""
    ) -WorkingDirectory $path -PassThru -WindowStyle Minimized

    return New-ApiResult -Success $true -Message "SyncMe backup started (PID $($proc.Id))" -Data ([PSCustomObject]@{
        Pid     = $proc.Id
        Script  = $backup
        Path    = $path
        Note    = "Backup runs in the background. Check SyncMe logs/Reports for progress."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
