# ReleaseDhcp.ps1
try {
    $release = ipconfig /release 2>&1 | Out-String
    Start-Sleep -Seconds 1
    $renew = ipconfig /renew 2>&1 | Out-String
    return New-ApiResult -Success $true -Message "DHCP release/renew completed" -Data ([PSCustomObject]@{
        Release = $release.Trim()
        Renew   = $renew.Trim()
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
