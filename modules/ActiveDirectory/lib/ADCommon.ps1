# modules/ActiveDirectory/lib/ADCommon.ps1
function Test-LocADAvailable {
    $domain = $env:USERDOMAIN
    $joined = $false
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs -and $cs.PartOfDomain) { $joined = $true }
    } catch { Write-Debug $_.Exception.Message }
    $mod = Get-Module -ListAvailable ActiveDirectory -ErrorAction SilentlyContinue
    return [PSCustomObject]@{
        DomainJoined = [bool]$joined
        Domain       = if ($joined) { [string]$cs.Domain } else { $domain }
        HasADModule  = [bool]$mod
        Available    = [bool]($joined -and $mod)
    }
}

function Import-LocADModule {
    $st = Test-LocADAvailable
    if (-not $st.Available) { return $st }
    Import-Module ActiveDirectory -ErrorAction Stop | Out-Null
    return $st
}
