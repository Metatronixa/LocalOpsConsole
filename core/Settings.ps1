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
    return $s.eventIntel
}

function Test-LocEventIntelEnabled {
    $s = Get-LocSettings
    if (-not $s) { return $true }
    if ($null -eq $s.PSObject.Properties['eventIntelEnabled']) { return $true }
    return [bool]$s.eventIntelEnabled
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

function Update-LocEventIntelPrefs {
    param([hashtable]$Prefs)
    $s = Get-LocSettings
    if (-not $s) { return $false }
    if (-not $s.eventIntel) {
        $s | Add-Member -NotePropertyName eventIntel -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $ei = $s.eventIntel
    foreach ($key in $Prefs.Keys) {
        $ei | Add-Member -NotePropertyName $key -NotePropertyValue $Prefs[$key] -Force
    }
    $s | Add-Member -NotePropertyName eventIntel -NotePropertyValue $ei -Force
    return (Save-LocSettings -Settings $s)
}
