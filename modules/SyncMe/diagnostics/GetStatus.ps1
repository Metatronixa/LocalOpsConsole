try {
    $path = Get-SyncMePath
    $bat = if ($path) { Join-Path $path "SyncMe.bat" } else { $null }
    $hostPs1 = if ($path) { Join-Path $path "SyncMe-Host.ps1" } else { $null }
    $backup = if ($path) { Join-Path $path "SyncMe-Backup.ps1" } else { $null }

    $listening = $false
    try {
        $c = Get-NetTCPConnection -LocalPort 17845 -State Listen -ErrorAction SilentlyContinue
        if ($c) { $listening = $true }
    }
    catch { }

    return New-ApiResult -Success $true -Message $(if ($path) { "SyncMe found" } else { "SyncMe path not configured" }) -Data ([PSCustomObject]@{
        Path            = $path
        SyncMeBat       = if ($bat) { Test-Path $bat } else { $false }
        HostScript      = if ($hostPs1) { Test-Path $hostPs1 } else { $false }
        BackupScript    = if ($backup) { Test-Path $backup } else { $false }
        ConsoleListening= $listening
        ConsoleUrl      = "http://127.0.0.1:17845/"
        Tip             = "Set syncMePath in settings.json if SyncMe is installed elsewhere."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
