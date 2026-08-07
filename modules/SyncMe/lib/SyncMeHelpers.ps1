# Resolve SyncMe install path from settings, registration, or sibling folder
function Get-SyncMePath {
    $settings = Get-LocSettings
    if ($settings.PSObject.Properties['syncMePath'] -and $settings.syncMePath) {
        $p = [string]$settings.syncMePath
        if (Test-Path $p) { return [System.IO.Path]::GetFullPath($p) }
    }

    if (Get-Command Get-LocSyncMeRegistration -ErrorAction SilentlyContinue) {
        $reg = Get-LocSyncMeRegistration
        if ($reg -and $reg.installPath -and (Test-Path -LiteralPath ([string]$reg.installPath))) {
            return [System.IO.Path]::GetFullPath([string]$reg.installPath)
        }
    }

    $root = Get-LocRoot
    $sibling = [System.IO.Path]::GetFullPath((Join-Path $root "..\SyncMe"))
    if (Test-Path $sibling) { return $sibling }
    return $null
}
