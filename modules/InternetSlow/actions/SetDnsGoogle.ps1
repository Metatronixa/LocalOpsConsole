# SetDnsGoogle.ps1
param([string]$InterfaceAlias = "")

try {
    if ([string]::IsNullOrWhiteSpace($InterfaceAlias)) {
        $a = Get-LocActiveAdapterInfo
        $InterfaceAlias = if ($a) { $a.Name } else { (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1).Name }
    }
    if (-not $InterfaceAlias) { return New-ApiResult -Success $false -Message "No adapter found" }
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses @("8.8.8.8", "8.8.4.4") -ErrorAction Stop
    return New-ApiResult -Success $true -Message "DNS set to Google on $InterfaceAlias" -Data ([PSCustomObject]@{
        InterfaceAlias = $InterfaceAlias
        Servers        = "8.8.8.8, 8.8.4.4"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
