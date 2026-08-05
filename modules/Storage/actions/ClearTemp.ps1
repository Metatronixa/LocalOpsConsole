param(
    [bool]$IncludeUserTemp = $true,
    [bool]$IncludeWindowsTemp = $true
)

try {
    $targets = @()
    if ($IncludeUserTemp) {
        $targets += $env:TEMP
        $targets += (Join-Path $env:LOCALAPPDATA "Temp")
    }
    if ($IncludeWindowsTemp) {
        $targets += "$env:SystemRoot\Temp"
    }

    $freedBytes = 0L
    $removed = 0
    $errors = 0

    foreach ($dir in ($targets | Select-Object -Unique)) {
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -Path $dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $size = 0L
                if (-not $_.PSIsContainer) { $size = $_.Length }
                else {
                    $size = (Get-ChildItem $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                    if (-not $size) { $size = 0 }
                }
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
                $freedBytes += $size
                $removed++
            }
            catch { $errors++ }
        }
    }

    return New-ApiResult -Success $true -Message "Temp cleanup complete" -Data ([PSCustomObject]@{
        FilesRemoved = $removed
        FreedMB      = [math]::Round($freedBytes / 1MB, 2)
        Errors       = $errors
        Targets      = @($targets)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
