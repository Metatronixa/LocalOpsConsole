param([hashtable]$Params = @{})
try {
    $st = Import-LocADModule
    if (-not $st.Available) { return New-ApiResult -Success $false -Message 'AD not available' -StatusCode 503 }
    $id = Assert-LocADUserName -Identity $(if ($Params.Identity) { $Params.Identity } elseif ($Params.User) { $Params.User } else { '' })
    Unlock-ADAccount -Identity $id -ErrorAction Stop
    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'ActiveDirectory' -Category 'Action' -Summary "Unlocked $id" -Data @{ Identity = $id }
    }
    return New-ApiResult -Success $true -Message "Unlocked $id" -Data @{ Identity = $id; Action = 'Unlock-ADUser' }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
