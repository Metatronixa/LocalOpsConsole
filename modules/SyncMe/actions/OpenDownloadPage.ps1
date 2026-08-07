try {
    $url = "https://www.syncme.co.za/"
    return New-ApiResult -Success $true -Message "Opening SyncMe website" -Data ([PSCustomObject]@{
        Url  = $url
        Note = "Download SyncMe from the site and install it. SyncMe can auto-register with LocalOps on the same PC, or set syncMePath in settings.json."
        Zip  = "https://www.syncme.co.za/updates/SyncMe-Setup-1.4.2.zip"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
