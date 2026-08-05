# TestPort.ps1
param(
    [string]$HostName = "1.1.1.1",
    [int]$Port = 443
)

try {
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return New-ApiResult -Success $false -Message "HostName required" -StatusCode 400
    }
    $result = Invoke-LocTcpConnect -HostName $HostName -Port $Port -TimeoutMs 2000
    return New-ApiResult -Success $true -Message $(if ($result.Success) { "Port open" } else { "Port closed or timeout" }) -Data $result
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
