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
