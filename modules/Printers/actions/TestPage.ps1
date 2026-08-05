param([Parameter(Mandatory)][string]$PrinterName)
try {
    $null = rundll32 printui.dll,PrintUIEntry /k /n "$PrinterName"
    return New-ApiResult -Success $true -Message "Test page requested for $PrinterName" -Data ([PSCustomObject]@{ PrinterName = $PrinterName })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
