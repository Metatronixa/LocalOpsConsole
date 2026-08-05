try {
    $devices = @()
    # Prefer modern cmdlet if available
    if (Get-Command Get-AudioDevice -ErrorAction SilentlyContinue) {
        Get-AudioDevice -List -ErrorAction SilentlyContinue | ForEach-Object {
            $devices += [PSCustomObject]@{
                Name     = $_.Name
                Type     = [string]$_.Type
                Default  = [bool]$_.Default
                ID       = $_.ID
            }
        }
    }
    else {
        Get-PnpDevice -Class Media,AudioEndpoint -ErrorAction SilentlyContinue | ForEach-Object {
            $devices += [PSCustomObject]@{
                Name    = $_.FriendlyName
                Type    = $_.Class
                Default = $false
                ID      = $_.InstanceId
                Status  = [string]$_.Status
            }
        }
    }

    $svc = Get-Service Audiosrv, AudioEndpointBuilder -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status }
    }

    return New-ApiResult -Success $true -Message ("{0} audio device(s)" -f $devices.Count) -Data ([PSCustomObject]@{
        Devices  = @($devices)
        Services = @($svc)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
