param([hashtable]$Params = @{})
$null = $Params
try {
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $size = [double]$_.Size; $free = [double]$_.FreeSpace
        [PSCustomObject]@{
            DeviceID = $_.DeviceID
            SizeGB = [math]::Round($size/1GB,1)
            FreeGB = [math]::Round($free/1GB,1)
            PctFree = if ($size -gt 0) { [math]::Round(100*$free/$size,1) } else { 0 }
        }
    })
    return New-ApiResult -Success $true -Message ("{0} volume(s)" -f $disks.Count) -Data @{ Available = $true; Disks = @($disks) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
