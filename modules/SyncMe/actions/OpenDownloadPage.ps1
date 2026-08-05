try {
    $url = "https://www.syncme.co.za/"
    return New-ApiResult -Success $true -Message "Opening SyncMe website" -Data ([PSCustomObject]@{
        Url  = $url
        Note = "Download SyncMe from the site, install it, then set syncMePath in settings.json if needed."
        Zip  = "https://www.syncme.co.za/updates/SyncMe-Setup-1.4.2.zip"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
