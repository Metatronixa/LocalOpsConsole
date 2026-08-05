# GetInternetTimeline.ps1
try {
    $events = Get-LocInternetTimeline
    return New-ApiResult -Success $true -Message ("{0} timeline event(s)" -f $events.Count) -Data @($events)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
