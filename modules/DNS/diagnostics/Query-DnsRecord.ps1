param([hashtable]$Params = @{})
try {
    $name = if ($Params.Name) { [string]$Params.Name } else { 'localhost' }
    $type = if ($Params.Type) { [string]$Params.Type } else { 'A' }
    $r = @(Resolve-DnsName -Name $name -Type $type -ErrorAction Stop | Select-Object -First 20 Name, Type, IPAddress, NameHost, TTL)
    return New-ApiResult -Success $true -Message ("Query {0} {1}" -f $name, $type) -Data @{ Available = $true; Records = @($r) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
