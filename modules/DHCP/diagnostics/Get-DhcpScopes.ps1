param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocDhcpServerAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'DHCP Server role not present' -Data @{ Available = $false } }
    Import-Module DhcpServer -ErrorAction Stop | Out-Null
    $scopes = @(Get-DhcpServerv4Scope -ErrorAction Stop | Select-Object ScopeId, Name, State, StartRange, EndRange, LeaseDuration)
    return New-ApiResult -Success $true -Message ("{0} scope(s)" -f $scopes.Count) -Data @{ Available = $true; Scopes = @($scopes) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
