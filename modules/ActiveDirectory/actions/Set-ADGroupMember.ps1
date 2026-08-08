param([hashtable]$Params = @{})
try {
    $st = Import-LocADModule
    if (-not $st.Available) { return New-ApiResult -Success $false -Message 'AD not available' -StatusCode 503 }
    $id = Assert-LocADUserName -Identity $(if ($Params.Identity) { $Params.Identity } elseif ($Params.User) { $Params.User } else { '' })
    $group = Assert-LocADGroupName -Group $(if ($Params.Group) { $Params.Group } else { '' })
    $op = if ($Params.Operation) { [string]$Params.Operation } else { 'Add' }
    if (Test-LocADPrivilegedGroup -Group $group) {
        if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
            Add-LocSystemTimelineEntry -Source 'ActiveDirectory' -Category 'Security' -Summary "Privileged group change requested: $group / $id" -Data @{ Identity = $id; Group = $group; Operation = $op; RiskLevel = 'HIGH' }
        }
    }
    if ($op -match '(?i)remove') {
        Remove-ADGroupMember -Identity $group -Members $id -Confirm:$false -ErrorAction Stop
    } else {
        Add-ADGroupMember -Identity $group -Members $id -ErrorAction Stop
    }
    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'ActiveDirectory' -Category 'Action' -Summary "Group membership $op : $id -> $group" -Data @{ Identity = $id; Group = $group; Operation = $op; RiskLevel = 'HIGH' }
    }
    return New-ApiResult -Success $true -Message "Group membership updated" -Data @{ Identity = $id; Group = $group; Operation = $op }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
