function Test-LocHyperVAvailable {
    $role = $false
    try { $f = Get-WindowsFeature Hyper-V -ErrorAction SilentlyContinue; if ($f -and $f.InstallState -eq 'Installed') { $role = $true } } catch { Write-Debug $_.Exception.Message }
    $mod = [bool](Get-Module -ListAvailable Hyper-V -ErrorAction SilentlyContinue)
    return [PSCustomObject]@{ Available = ($role -or $mod); HasModule = $mod; HasRole = $role }
}
