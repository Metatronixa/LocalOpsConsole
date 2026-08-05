try {
    $profiles = @()
    Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special } | ForEach-Object {
        $path = $_.LocalPath
        $exists = $false
        if ($path) {
            try { $exists = Test-Path -LiteralPath $path } catch { $exists = $false }
        }
        # Intentionally no recursive size scan — that times out on large profiles.
        $profiles += [PSCustomObject]@{
            LocalPath   = $path
            SID         = $_.SID
            Loaded      = [bool]$_.Loaded
            PathExists  = $exists
            SizeMB      = $null
            LastUseTime = if ($_.LastUseTime) { $_.LastUseTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        }
    }
    return New-ApiResult -Success $true -Message ("{0} profile(s) (size omitted for speed)" -f $profiles.Count) -Data @($profiles)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
