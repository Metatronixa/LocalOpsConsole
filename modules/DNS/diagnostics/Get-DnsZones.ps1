param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocDnsServerAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'DNS Server role not present' -Data @{ Available = $false } }
    Import-Module DnsServer -ErrorAction SilentlyContinue | Out-Null
    $zones = @(Get-DnsServerZone -ErrorAction Stop | Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone)
    return New-ApiResult -Success $true -Message ("{0} zone(s)" -f $zones.Count) -Data @{ Available = $true; Zones = @($zones) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
