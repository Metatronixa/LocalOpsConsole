function Test-LocDhcpServerAvailable {
    $role = $false
    try { $f = Get-WindowsFeature DHCP -ErrorAction SilentlyContinue; if ($f -and $f.InstallState -eq 'Installed') { $role = $true } } catch { Write-Debug $_.Exception.Message }
    $mod = [bool](Get-Module -ListAvailable DhcpServer -ErrorAction SilentlyContinue)
    return [PSCustomObject]@{ Available = ($role -or $mod); HasModule = $mod; HasRole = $role }
}
