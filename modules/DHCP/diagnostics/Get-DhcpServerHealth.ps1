param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocDhcpServerAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'DHCP Server role not present' -Data @{ Available = $false; Status = $st } }
    Import-Module DhcpServer -ErrorAction SilentlyContinue | Out-Null
    $scopes = @(Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Select-Object -First 50 ScopeId, Name, State, StartRange, EndRange)
    return New-ApiResult -Success $true -Message 'DHCP health' -Data @{ Available = $true; ScopeCount = $scopes.Count; Scopes = @($scopes) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
