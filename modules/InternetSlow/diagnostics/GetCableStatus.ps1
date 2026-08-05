# GetCableStatus.ps1
try {
    $rows = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        -not $_.Virtual -and ($_.MediaType -match '802\.3|Ethernet' -or $_.InterfaceDescription -match 'Ethernet')
    } | ForEach-Object {
        [PSCustomObject]@{
            Name           = $_.Name
            Status         = [string]$_.Status
            MediaConnected = [bool]$_.MediaConnected
            LinkSpeed      = [string]$_.LinkSpeed
        }
    })

    return New-ApiResult -Success $true -Message ("{0} physical Ethernet adapter(s)" -f $rows.Count) -Data @($rows)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
