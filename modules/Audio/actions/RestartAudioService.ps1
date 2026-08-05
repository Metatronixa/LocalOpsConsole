try {
    Restart-Service -Name Audiosrv, AudioEndpointBuilder -Force -ErrorAction Stop
    $svc = Get-Service Audiosrv, AudioEndpointBuilder | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status }
    }
    return New-ApiResult -Success $true -Message "Audio services restarted" -Data ([PSCustomObject]@{ Services = @($svc) })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
