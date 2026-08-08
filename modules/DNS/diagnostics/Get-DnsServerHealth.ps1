param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocDnsServerAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'DNS Server role not present' -Data @{ Available = $false; Status = $st } }
    Import-Module DnsServer -ErrorAction SilentlyContinue | Out-Null
    $zones = @(Get-DnsServerZone -ErrorAction SilentlyContinue | Select-Object -First 50 ZoneName, ZoneType, IsDsIntegrated)
    return New-ApiResult -Success $true -Message 'DNS server health' -Data @{ Available = $true; ZoneCount = $zones.Count; Zones = @($zones) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
