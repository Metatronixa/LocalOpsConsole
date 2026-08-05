try {
    $results = @()
    $physical = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physical) {
        foreach ($d in $physical) {
            $health = $d.HealthStatus
            $results += [PSCustomObject]@{
                FriendlyName = $d.FriendlyName
                MediaType    = [string]$d.MediaType
                SizeGB       = [math]::Round($d.Size / 1GB, 2)
                HealthStatus = [string]$health
                Operational  = [string]$d.OperationalStatus
                BusType      = [string]$d.BusType
            }
        }
    }
    else {
        Get-CimInstance Win32_DiskDrive -ErrorAction Stop | ForEach-Object {
            $results += [PSCustomObject]@{
                FriendlyName = $_.Model
                MediaType    = $_.InterfaceType
                SizeGB       = [math]::Round($_.Size / 1GB, 2)
                HealthStatus = "Unknown"
                Operational  = $_.Status
                BusType      = $_.InterfaceType
            }
        }
    }
    return New-ApiResult -Success $true -Message "SMART / disk health" -Data @($results)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
