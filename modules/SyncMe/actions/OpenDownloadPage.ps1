try {
    $url = "https://www.syncme.co.za/updates/SyncMe-Setup-1.4.2.zip"
    return New-ApiResult -Success $true -Message "Opening SyncMe download page" -Data ([PSCustomObject]@{
        Url  = $url
        Note = "Install SyncMe, then set syncMePath in settings.json if needed."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
