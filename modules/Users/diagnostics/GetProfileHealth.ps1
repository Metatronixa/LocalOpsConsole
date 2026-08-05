try {
    $profiles = @()
    Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special } | ForEach-Object {
        $path = $_.LocalPath
        $exists = Test-Path $path
        $sizeMB = $null
        if ($exists) {
            try {
                $sizeMB = [math]::Round(((Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB), 1)
            }
            catch { }
        }
        $profiles += [PSCustomObject]@{
            LocalPath   = $path
            SID         = $_.SID
            Loaded      = [bool]$_.Loaded
            PathExists  = $exists
            SizeMB      = $sizeMB
            LastUseTime = if ($_.LastUseTime) { $_.LastUseTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        }
    }
    return New-ApiResult -Success $true -Message ("{0} profile(s)" -f $profiles.Count) -Data @($profiles)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
