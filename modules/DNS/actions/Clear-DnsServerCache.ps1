param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocDnsServerAvailable
    if (-not $st.Available) { return New-ApiResult -Success $false -Message 'DNS Server role not present' -StatusCode 503 }
    Import-Module DnsServer -ErrorAction Stop | Out-Null
    Clear-DnsServerCache -Force -ErrorAction Stop
    return New-ApiResult -Success $true -Message 'DNS server cache cleared' -Data @{ Action = 'Clear-DnsServerCache' }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
