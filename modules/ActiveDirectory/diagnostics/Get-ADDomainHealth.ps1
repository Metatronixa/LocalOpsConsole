param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Import-LocADModule
    if (-not $st.Available) {
        return New-ApiResult -Success $true -Message 'AD not available on this host' -Data @{ Available = $false; Status = $st }
    }
    $domain = Get-ADDomain -ErrorAction Stop
    $dcs = @(Get-ADDomainController -Filter * -ErrorAction SilentlyContinue | Select-Object -First 20 Name, IPv4Address, OperatingSystem, IsGlobalCatalog)
    return New-ApiResult -Success $true -Message 'AD domain health' -Data @{
        Available     = $true
        Domain        = $domain.DNSRoot
        NetBIOSName   = $domain.NetBIOSName
        DomainMode    = [string]$domain.DomainMode
        PDCEmulator   = $domain.PDCEmulator
        DomainControllers = @($dcs)
    }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -Data @{ Available = $false }
}
