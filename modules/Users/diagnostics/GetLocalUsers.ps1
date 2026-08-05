try {
    $users = Get-LocalUser -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name            = $_.Name
            Enabled         = [bool]$_.Enabled
            Description     = $_.Description
            LastLogon       = if ($_.LastLogon) { $_.LastLogon.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            PasswordExpires = if ($_.PasswordExpires) { $_.PasswordExpires.ToString("yyyy-MM-dd") } else { $null }
            PrincipalSource = [string]$_.PrincipalSource
        }
    }
    return New-ApiResult -Success $true -Message ("{0} local user(s)" -f @($users).Count) -Data @($users)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
