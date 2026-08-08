function Test-LocGpoAvailable {
    $joined = $false
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue; if ($cs -and $cs.PartOfDomain) { $joined = $true } } catch { Write-Debug $_.Exception.Message }
    $mod = [bool](Get-Module -ListAvailable GroupPolicy -ErrorAction SilentlyContinue)
    return [PSCustomObject]@{ Available = $joined; DomainJoined = $joined; HasModule = $mod }
}
