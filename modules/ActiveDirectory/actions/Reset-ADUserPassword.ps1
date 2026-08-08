param([hashtable]$Params = @{})
try {
    $st = Import-LocADModule
    if (-not $st.Available) { return New-ApiResult -Success $false -Message 'AD not available' -StatusCode 503 }
    $id = Assert-LocADUserName -Identity $(if ($Params.Identity) { $Params.Identity } elseif ($Params.User) { $Params.User } else { '' })
    if (-not $Params.Password -and -not $Params.NewPassword) {
        return New-ApiResult -Success $false -Message 'Password or NewPassword required' -StatusCode 400
    }
    $pwdPlain = if ($Params.NewPassword) { [string]$Params.NewPassword } else { [string]$Params.Password }
    # JSON/API supplies plaintext; convert via NetworkCredential to avoid ConvertTo-SecureString -AsPlainText
    $secure = [System.Net.NetworkCredential]::new('', $pwdPlain).SecurePassword
    Set-ADAccountPassword -Identity $id -NewPassword $secure -Reset -ErrorAction Stop
    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'ActiveDirectory' -Category 'Action' -Summary "Password reset for $id" -Data @{ Identity = $id; RiskLevel = 'MODERATE' }
    }
    return New-ApiResult -Success $true -Message "Password reset for $id" -Data @{ Identity = $id; Action = 'Reset-ADUserPassword' }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
