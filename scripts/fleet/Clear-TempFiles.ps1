# Clear-TempFiles.ps1 - Remove user and system temp files (best-effort)
$paths = @($env:TEMP, "$env:SystemRoot\Temp")
$removed = 0
foreach ($p in $paths) {
    if (-not (Test-Path $p)) { continue }
    Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
            $removed++
        }
        catch { Write-Debug $_.Exception.Message }
    }
}
Write-Output "Removed $removed temp items (best-effort)."
