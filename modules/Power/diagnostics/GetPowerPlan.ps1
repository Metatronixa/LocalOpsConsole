try {
    $schemes = powercfg /list 2>&1 | Out-String
    $active = powercfg /getactivescheme 2>&1 | Out-String
    $guid = $null
    if ($active -match "([0-9a-fA-F-]{36})") { $guid = $Matches[1] }
    return New-ApiResult -Success $true -Message "Power plans" -Data ([PSCustomObject]@{
        ActiveScheme = $active.Trim()
        ActiveGuid   = $guid
        Schemes      = $schemes.Trim()
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
