try {
    Start-MpScan -ScanType QuickScan -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Defender quick scan started" -Data ([PSCustomObject]@{ ScanType = "QuickScan" })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
