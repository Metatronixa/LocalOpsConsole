param([hashtable]$Params = @{})
try {
    $st = Import-LocADModule
    if (-not $st.Available) {
        return New-ApiResult -Success $true -Message 'AD not available' -Data @{ Available = $false; Status = $st }
    }
    $id = Assert-LocADUserName -Identity $(if ($Params.Identity) { $Params.Identity } elseif ($Params.User) { $Params.User } else { '' })
    $u = Get-ADUser -Identity $id -Properties LockedOut, Enabled, PasswordExpired, LastLogonDate, BadLogonCount, DistinguishedName -ErrorAction Stop
    return New-ApiResult -Success $true -Message "User $id" -Data @{
        Available = $true
        SamAccountName = $u.SamAccountName
        Enabled = [bool]$u.Enabled
        LockedOut = [bool]$u.LockedOut
        PasswordExpired = [bool]$u.PasswordExpired
        BadLogonCount = [int]$u.BadLogonCount
        LastLogonDate = if ($u.LastLogonDate) { $u.LastLogonDate.ToString('o') } else { $null }
        DistinguishedName = $u.DistinguishedName
    }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
