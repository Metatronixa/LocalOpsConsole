# modules/SyncMe/lib/SyncMeRegister.ps1 - ingest registration from SyncMe Backup PC

function Get-LocSyncMeRegistrationPath {
    return (Join-Path (Get-LocRoot) "data\syncme\registration.json")
}

function Get-LocSyncMeRegistration {
    $path = Get-LocSyncMeRegistrationPath
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Test-LocRequestIsLoopback {
    param([System.Net.HttpListenerRequest]$Request)
    try {
        $addr = $Request.RemoteEndPoint.Address
        if ($null -ne $addr) {
            return [System.Net.IPAddress]::IsLoopback($addr)
        }
    }
    catch { Write-Debug $_.Exception.Message }
    # Do not trust Host: alone — require a real loopback remote endpoint.
    return $false
}

function Test-LocSyncMeInstallPath {
    param([string]$InstallPath)
    if ([string]::IsNullOrWhiteSpace($InstallPath)) { return $false }
    if (-not (Test-Path -LiteralPath $InstallPath)) { return $false }
    $hostPs1 = Join-Path $InstallPath "SyncMe-Host.ps1"
    $bat = Join-Path $InstallPath "SyncMe.bat"
    return ((Test-Path -LiteralPath $hostPs1) -or (Test-Path -LiteralPath $bat))
}

function Save-LocSyncMeRegistration {
    param([hashtable]$Fields)

    $installPath = if ($Fields.ContainsKey('installPath')) { [string]$Fields['installPath'] } else { '' }
    $installPath = $installPath.Trim().TrimEnd('\', '/')

    if (-not [string]::IsNullOrWhiteSpace($installPath)) {
        if (-not (Test-LocSyncMeInstallPath -InstallPath $installPath)) {
            return @{
                Success    = $false
                Message    = "installPath must exist and contain SyncMe-Host.ps1 or SyncMe.bat"
                StatusCode = 400
                Data       = $null
            }
        }
    }

    $existing = Get-LocSyncMeRegistration
    $reg = [ordered]@{
        installPath = $(if (-not [string]::IsNullOrWhiteSpace($installPath)) { $installPath } elseif ($existing) { [string]$existing.installPath } else { '' })
        version     = $(if ($Fields.ContainsKey('version')) { [string]$Fields['version'] } elseif ($existing) { [string]$existing.version } else { '' })
        hostname    = $(if ($Fields.ContainsKey('hostname')) { [string]$Fields['hostname'] } elseif ($existing) { [string]$existing.hostname } else { $env:COMPUTERNAME })
        siteId      = $(if ($Fields.ContainsKey('siteId')) { [string]$Fields['siteId'] } elseif ($existing) { [string]$existing.siteId } else { '' })
        consoleUrl  = $(if ($Fields.ContainsKey('consoleUrl')) { [string]$Fields['consoleUrl'] } elseif ($existing) { [string]$existing.consoleUrl } else { 'http://127.0.0.1:17845/' })
        listening   = $(if ($Fields.ContainsKey('listening')) { [bool]$Fields['listening'] } elseif ($existing -and $null -ne $existing.listening) { [bool]$existing.listening } else { $false })
        success     = $(if ($Fields.ContainsKey('success')) { [bool]$Fields['success'] } elseif ($existing -and $null -ne $existing.success) { [bool]$existing.success } else { $null })
        summary     = $(if ($Fields.ContainsKey('summary')) { [string]$Fields['summary'] } elseif ($existing) { [string]$existing.summary } else { '' })
        setId       = $(if ($Fields.ContainsKey('setId')) { [string]$Fields['setId'] } elseif ($existing) { [string]$existing.setId } else { '' })
        setName     = $(if ($Fields.ContainsKey('setName')) { [string]$Fields['setName'] } elseif ($existing) { [string]$existing.setName } else { '' })
        endedUtc    = $(if ($Fields.ContainsKey('endedUtc')) { [string]$Fields['endedUtc'] } elseif ($existing) { [string]$existing.endedUtc } else { '' })
        receivedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    if ([string]::IsNullOrWhiteSpace([string]$reg.installPath)) {
        return @{
            Success    = $false
            Message    = "installPath is required (or a prior registration must exist)"
            StatusCode = 400
            Data       = $null
        }
    }

    $dir = Join-Path (Get-LocRoot) "data\syncme"
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Get-LocSyncMeRegistrationPath
    $json = ($reg | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($path, $json + "`r`n", [System.Text.UTF8Encoding]::new($false))

    if (Test-LocSyncMeInstallPath -InstallPath ([string]$reg.installPath)) {
        $s = Get-LocSettings
        if ($s) {
            $s | Add-Member -NotePropertyName syncMePath -NotePropertyValue ([string]$reg.installPath) -Force
            [void](Save-LocSettings -Settings $s)
        }
    }

    return @{
        Success    = $true
        Message    = "SyncMe registered"
        StatusCode = 200
        Data       = [pscustomobject]$reg
    }
}
