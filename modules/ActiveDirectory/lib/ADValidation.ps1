# modules/ActiveDirectory/lib/ADValidation.ps1
function Assert-LocADUserName {
    param([string]$Identity)
    if ([string]::IsNullOrWhiteSpace($Identity)) { throw 'Identity (user) required' }
    if ($Identity -match '[;|&<>`]') { throw 'Identity contains forbidden characters' }
    if ($Identity.Length -gt 256) { throw 'Identity too long' }
    return $Identity.Trim()
}

function Assert-LocADGroupName {
    param([string]$Group)
    if ([string]::IsNullOrWhiteSpace($Group)) { throw 'Group required' }
    if ($Group -match '[;|&<>`]') { throw 'Group contains forbidden characters' }
    return $Group.Trim()
}

function Test-LocADPrivilegedGroup {
    param([string]$Group)
    $priv = @('Domain Admins','Enterprise Admins','Schema Admins','Administrators','Account Operators')
    return ($priv -contains $Group)
}
