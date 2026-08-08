# core/Settings.ps1 - Load version + runtime settings

$script:LocSettings = $null
$script:LocVersion = $null
$script:LocRoot = $null

function Initialize-LocSettings {
    param([string]$RootPath)

    $script:LocRoot = $RootPath
    $versionPath = Join-Path $RootPath "version.json"
    $settingsPath = Join-Path $RootPath "settings.json"
    $versionFile = Join-Path $RootPath "VERSION"

    if (Test-Path $versionPath) {
        $script:LocVersion = Get-Content $versionPath -Raw | ConvertFrom-Json
    }
    else {
        $ver = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.0.0" }
        $script:LocVersion = [PSCustomObject]@{ name = "LocalOpsConsole"; version = $ver }
    }

    if (Test-Path $settingsPath) {
        $script:LocSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    }
    else {
        $script:LocSettings = [PSCustomObject]@{
            port                 = 8080
            cacheTtlSeconds      = 20
            taskIntervalSeconds  = 10
            logRetentionDays     = 14
            bindHost             = "localhost"
            productMode          = "desktop"
        }
    }
}

function Get-LocVersion {
    return $script:LocVersion
}

function Get-LocSettings {
    return $script:LocSettings
}

function Get-LocRoot {
    return $script:LocRoot
}

<#
.SYNOPSIS
  Map settings.bindHost to HttpListener prefix hostnames.
.NOTES
  Concrete LAN IPs also include localhost so start.ps1 / the local UI keep working.
  0.0.0.0 / * / + map to HTTP.sys strong wildcard '+' only (covers all interfaces including loopback).
#>
function Resolve-LocHttpListenHosts {
    param([string]$BindHost = "localhost")

    $bind = if ($BindHost) { $BindHost.Trim() } else { "localhost" }
    if ([string]::IsNullOrWhiteSpace($bind)) { $bind = "localhost" }

    if ($bind -match '^(?i)(0\.0\.0\.0|\*|\+)$') {
        return @("+")
    }
    if ($bind -match '^(?i)(localhost|127\.0\.0\.1)$') {
        return @("localhost")
    }
    # Specific interface: listen there AND on loopback (launcher always opens localhost).
    return @($bind, "localhost")
}

function Get-LocEventIntelSettings {
    $s = Get-LocSettings
    $defaults = [PSCustomObject]@{
        sysmonOptional       = $true
        eventRetentionHours  = 72
        incidentArchiveDays  = 30
        notifyLevel          = "Warning"
        notifyCategories     = @("*")
        quietHours           = [PSCustomObject]@{ enabled = $false; start = "22:00"; end = "07:00" }
        maintenanceWindow    = [PSCustomObject]@{ enabled = $false; start = $null; end = $null }
        businessHours        = [PSCustomObject]@{ enabled = $false; start = "08:00"; end = "18:00"; days = @(1, 2, 3, 4, 5) }
        channels             = [PSCustomObject]@{
            desktop = $true; dashboard = $true; email = $false
            teams = $false; slack = $false; discord = $false
            webhook = $false; syslog = $false
        }
        channelConfig        = [PSCustomObject]@{
            email = @{}; teams = @{}; slack = @{}; discord = @{}; webhook = @{}; syslog = @{}
        }
    }
    if (-not $s -or -not $s.eventIntel) { return $defaults }

    $ei = $s.eventIntel
    # Ensure inbox/desktop defaults stay on when keys are missing from older settings.json
    $ch = if ($ei.channels) { $ei.channels } else { [PSCustomObject]@{} }
    $mergedChannels = [PSCustomObject]@{
        desktop  = if ($null -ne $ch.PSObject.Properties['desktop']) { [bool]$ch.desktop } else { $true }
        dashboard = if ($null -ne $ch.PSObject.Properties['dashboard']) { [bool]$ch.dashboard } else { $true }
        email    = if ($null -ne $ch.PSObject.Properties['email']) { [bool]$ch.email } else { $false }
        teams    = if ($null -ne $ch.PSObject.Properties['teams']) { [bool]$ch.teams } else { $false }
        slack    = if ($null -ne $ch.PSObject.Properties['slack']) { [bool]$ch.slack } else { $false }
        discord  = if ($null -ne $ch.PSObject.Properties['discord']) { [bool]$ch.discord } else { $false }
        webhook  = if ($null -ne $ch.PSObject.Properties['webhook']) { [bool]$ch.webhook } else { $false }
        syslog   = if ($null -ne $ch.PSObject.Properties['syslog']) { [bool]$ch.syslog } else { $false }
    }
    $ei | Add-Member -NotePropertyName channels -NotePropertyValue $mergedChannels -Force
    return $ei
}

function Test-LocEventIntelEnabled {
    $s = Get-LocSettings
    if (-not $s) { return $true }
    if ($null -eq $s.PSObject.Properties['eventIntelEnabled']) { return $true }
    return [bool]$s.eventIntelEnabled
}

function Get-LocProductMode {
    if (Get-Command Resolve-LocProductMode -ErrorAction SilentlyContinue) {
        return Resolve-LocProductMode
    }
    $s = Get-LocSettings
    $mode = "desktop"
    if ($s -and $s.PSObject.Properties['productMode'] -and -not [string]::IsNullOrWhiteSpace([string]$s.productMode)) {
        $mode = ([string]$s.productMode).Trim().ToLowerInvariant()
    }
    if ($mode -notin @("desktop", "appliance")) { $mode = "desktop" }
    return $mode
}

function Save-LocSettings {
    param([object]$Settings = $null)
    if ($null -eq $Settings) { $Settings = $script:LocSettings }
    if ($null -eq $Settings) { return $false }
    $path = Join-Path (Get-LocRoot) "settings.json"
    try {
        $json = $Settings | ConvertTo-Json -Depth 12 -Compress:$false
        $tmp = "$path.tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path $path) { Remove-Item $path -Force }
        Move-Item $tmp $path -Force
        $script:LocSettings = $Settings
        return $true
    }
    catch {
        Write-LocLog -Module "CORE" -Action "SaveSettings" -Level "ERROR" -Message $_.Exception.Message
        return $false
    }
}

function ConvertTo-LocPlainObject {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [hashtable]) {
        $o = [PSCustomObject]@{}
        foreach ($k in $InputObject.Keys) {
            $o | Add-Member -NotePropertyName ([string]$k) -NotePropertyValue (ConvertTo-LocPlainObject $InputObject[$k]) -Force
        }
        return $o
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $arr = @()
        foreach ($item in $InputObject) { $arr += ,(ConvertTo-LocPlainObject $item) }
        return $arr
    }
    if ($InputObject -is [PSCustomObject] -or ($null -ne $InputObject.PSObject -and $InputObject.PSObject.Properties.Count -gt 0 -and -not ($InputObject -is [ValueType]) -and -not ($InputObject -is [string]))) {
        if ($InputObject -is [ValueType] -or $InputObject -is [string]) { return $InputObject }
        $o = [PSCustomObject]@{}
        foreach ($p in $InputObject.PSObject.Properties) {
            $o | Add-Member -NotePropertyName $p.Name -NotePropertyValue (ConvertTo-LocPlainObject $p.Value) -Force
        }
        return $o
    }
    return $InputObject
}

function Merge-LocChannelConfig {
    param(
        $Existing,
        $Incoming
    )
    $base = if ($Existing) { ConvertTo-LocPlainObject $Existing } else {
        [PSCustomObject]@{
            email = [PSCustomObject]@{}; teams = [PSCustomObject]@{}; slack = [PSCustomObject]@{}
            discord = [PSCustomObject]@{}; webhook = [PSCustomObject]@{}; syslog = [PSCustomObject]@{}
        }
    }
    if (-not $Incoming) { return $base }

    $inObj = ConvertTo-LocPlainObject $Incoming
    foreach ($chName in @('email', 'teams', 'slack', 'discord', 'webhook', 'syslog')) {
        if (-not $inObj.PSObject.Properties[$chName]) { continue }
        $inCh = $inObj.$chName
        if ($null -eq $inCh) { continue }
        $exCh = if ($base.PSObject.Properties[$chName]) { $base.$chName } else { [PSCustomObject]@{} }
        if (-not $exCh) { $exCh = [PSCustomObject]@{} }
        foreach ($p in $inCh.PSObject.Properties) {
            $val = $p.Value
            # Blank / placeholder password keeps the stored secret
            if ($p.Name -eq 'password') {
                $s = if ($null -eq $val) { '' } else { [string]$val }
                if ([string]::IsNullOrWhiteSpace($s) -or $s -eq '********') { continue }
            }
            $exCh | Add-Member -NotePropertyName $p.Name -NotePropertyValue $val -Force
        }
        $base | Add-Member -NotePropertyName $chName -NotePropertyValue $exCh -Force
    }
    return $base
}

function Get-LocEventIntelSettingsForApi {
    $ei = Get-LocEventIntelSettings
    $clone = ConvertTo-LocPlainObject $ei
    if (-not $clone) { return $ei }
    $cc = $clone.channelConfig
    if ($cc -and $cc.email) {
        $hasPass = $false
        if ($cc.email.PSObject.Properties['password'] -and -not [string]::IsNullOrWhiteSpace([string]$cc.email.password)) {
            $hasPass = $true
        }
        $cc.email | Add-Member -NotePropertyName password -NotePropertyValue '' -Force
        $cc.email | Add-Member -NotePropertyName passwordSet -NotePropertyValue $hasPass -Force
    }
    return $clone
}

function Update-LocEventIntelPrefs {
    param([hashtable]$Prefs)
    $s = Get-LocSettings
    if (-not $s) { return $false }
    if (-not $s.eventIntel) {
        $s | Add-Member -NotePropertyName eventIntel -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $ei = $s.eventIntel
    foreach ($key in $Prefs.Keys) {
        if ($key -eq 'channelConfig') {
            $merged = Merge-LocChannelConfig -Existing $ei.channelConfig -Incoming $Prefs[$key]
            $ei | Add-Member -NotePropertyName channelConfig -NotePropertyValue $merged -Force
            continue
        }
        $val = $Prefs[$key]
        if ($val -is [hashtable]) { $val = ConvertTo-LocPlainObject $val }
        $ei | Add-Member -NotePropertyName $key -NotePropertyValue $val -Force
    }
    $s | Add-Member -NotePropertyName eventIntel -NotePropertyValue $ei -Force
    return (Save-LocSettings -Settings $s)
}
