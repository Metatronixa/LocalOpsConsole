# RestartNla.ps1 — Network Location Awareness
try {
    Restart-Service -Name NlaSvc -Force -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Network Location Awareness service restarted"
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
