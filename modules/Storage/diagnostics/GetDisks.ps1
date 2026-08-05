try {
    $disks = @()
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop | ForEach-Object {
        $size = [double]$_.Size
        $free = [double]$_.FreeSpace
        $used = $size - $free
        $freePct = if ($size -gt 0) { [math]::Round(($free / $size) * 100, 0) } else { 0 }
        $disks += [PSCustomObject]@{
            DeviceID    = $_.DeviceID
            VolumeName  = if ($_.VolumeName) { $_.VolumeName } else { "Local Disk" }
            FileSystem  = $_.FileSystem
            SizeGB      = [math]::Round($size / 1GB, 2)
            FreeSpaceGB = [math]::Round($free / 1GB, 2)
            UsedSizeGB  = [math]::Round($used / 1GB, 2)
            FreePct     = $freePct
            LowSpace    = ($freePct -lt 15)
        }
    }
    return New-ApiResult -Success $true -Message "Logical volumes" -Data @($disks)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
