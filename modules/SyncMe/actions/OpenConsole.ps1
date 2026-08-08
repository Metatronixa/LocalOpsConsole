try {
    $path = Get-SyncMePath
    if (-not $path) {
        return New-ApiResult -Success $false -Message "SyncMe path not found. Let SyncMe auto-register on this PC, or set syncMePath in settings.json."
    }

    $bat = Join-Path $path "SyncMe.bat"
    $hostPs1 = Join-Path $path "SyncMe-Host.ps1"
    if (-not (Test-Path $hostPs1) -and -not (Test-Path $bat)) {
        return New-ApiResult -Success $false -Message "Neither SyncMe.bat nor SyncMe-Host.ps1 found in $path"
    }

    $listening = $false
    try {
        if (Get-NetTCPConnection -LocalPort 17845 -State Listen -ErrorAction SilentlyContinue) { $listening = $true }
    } catch { Write-Debug $_.Exception.Message }

    if (-not $listening) {
        if (Test-Path $bat) {
            Start-Process -FilePath $bat -WorkingDirectory $path
        }
        else {
            Start-Process -FilePath "powershell.exe" -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass",
                "-File", "`"$hostPs1`"", "-Port", "17845", "-OpenView", "auto"
            ) -WorkingDirectory $path
        }
        Start-Sleep -Seconds 2
    }

    Start-Process "http://127.0.0.1:17845/"

    return New-ApiResult -Success $true -Message "SyncMe console opening" -Data ([PSCustomObject]@{
        Url  = "http://127.0.0.1:17845/"
        Path = $path
        WasAlreadyRunning = $listening
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
