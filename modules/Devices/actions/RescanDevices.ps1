try {
    $null = pnputil /scan-devices 2>&1 | Out-String
    return New-ApiResult -Success $true -Message "PnP device rescan requested" -Data ([PSCustomObject]@{ Action = "scan-devices" })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
