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
    catch { Write-Debug $_.Exception.Message }

    $reg = $null
    if (Get-Command Get-LocSyncMeRegistration -ErrorAction SilentlyContinue) {
        $reg = Get-LocSyncMeRegistration
    }

    $registered = $false
    $lastSeenUtc = ''
    $version = ''
    $hostname = ''
    $siteId = ''
    $lastRun = $null
    if ($reg) {
        $registered = $true
        $lastSeenUtc = [string]$reg.receivedUtc
        $version = [string]$reg.version
        $hostname = [string]$reg.hostname
        $siteId = [string]$reg.siteId
        $lastRun = [PSCustomObject]@{
            Success  = $(if ($null -ne $reg.success) { [bool]$reg.success } else { $null })
            Summary  = [string]$reg.summary
            SetId    = [string]$reg.setId
            SetName  = [string]$reg.setName
            EndedUtc = [string]$reg.endedUtc
        }
    }

    return New-ApiResult -Success $true -Message $(if ($path) { "SyncMe found" } else { "SyncMe path not configured" }) -Data ([PSCustomObject]@{
        Path             = $path
        SyncMeBat        = if ($bat) { Test-Path $bat } else { $false }
        HostScript       = if ($hostPs1) { Test-Path $hostPs1 } else { $false }
        BackupScript     = if ($backup) { Test-Path $backup } else { $false }
        ConsoleListening = $listening
        ConsoleUrl       = $(if ($reg -and $reg.consoleUrl) { [string]$reg.consoleUrl } else { "http://127.0.0.1:17845/" })
        Registered       = $registered
        LastSeenUtc      = $lastSeenUtc
        Version          = $version
        Hostname         = $hostname
        SiteId           = $siteId
        LastRun          = $lastRun
        Tip              = "SyncMe can auto-register when running on this PC. Or set syncMePath in settings.json."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
