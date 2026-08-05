# SetDnsDhcp.ps1
param([string]$InterfaceAlias = "")

try {
    if ([string]::IsNullOrWhiteSpace($InterfaceAlias)) {
        $a = Get-LocActiveAdapterInfo
        $InterfaceAlias = if ($a) { $a.Name } else { (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1).Name }
    }
    if (-not $InterfaceAlias) { return New-ApiResult -Success $false -Message "No adapter found" }
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses -ErrorAction Stop
    return New-ApiResult -Success $true -Message "DNS reset to DHCP on $InterfaceAlias" -Data ([PSCustomObject]@{
        InterfaceAlias = $InterfaceAlias
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
