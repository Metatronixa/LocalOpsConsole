param([string]$PrinterName = "")
try {
    $removed = 0
    if ($PrinterName) {
        Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-PrintJob -PrinterName $_.PrinterName -ID $_.Id -ErrorAction SilentlyContinue
            $removed++
        }
    }
    else {
        Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
            Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-PrintJob -PrinterName $_.PrinterName -ID $_.Id -ErrorAction SilentlyContinue
                $removed++
            }
        }
        # Also clear spool directory leftovers
        $spool = "$env:SystemRoot\System32\spool\PRINTERS"
        if (Test-Path $spool) {
            Get-ChildItem $spool -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    return New-ApiResult -Success $true -Message "Cleared $removed print job(s)" -Data ([PSCustomObject]@{ Removed = $removed; PrinterName = $PrinterName })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
