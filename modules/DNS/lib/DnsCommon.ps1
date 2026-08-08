# modules/DNS/lib/DnsCommon.ps1
function Test-LocDnsServerAvailable {
    $role = $false
    try {
        $f = Get-WindowsFeature DNS -ErrorAction SilentlyContinue
        if ($f -and $f.InstallState -eq 'Installed') { $role = $true }
    } catch { Write-Debug $_.Exception.Message }
    $mod = [bool](Get-Module -ListAvailable DnsServer -ErrorAction SilentlyContinue)
    return [PSCustomObject]@{ Available = ($role -or $mod); HasModule = $mod; HasRole = $role }
}
