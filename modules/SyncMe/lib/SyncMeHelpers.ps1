# Resolve SyncMe install path from settings or sibling folder
function Get-SyncMePath {
    $settings = Get-LocSettings
    if ($settings.PSObject.Properties['syncMePath'] -and $settings.syncMePath) {
        $p = [string]$settings.syncMePath
        if (Test-Path $p) { return [System.IO.Path]::GetFullPath($p) }
    }
    $root = Get-LocRoot
    $sibling = [System.IO.Path]::GetFullPath((Join-Path $root "..\SyncMe"))
    if (Test-Path $sibling) { return $sibling }
    return $null
}
