# GetNetStatistics.ps1
try {
    $rows = @(Get-NetAdapterStatistics -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            Name              = $_.Name
            ReceivedBytes     = $_.ReceivedBytes
            SentBytes         = $_.SentBytes
            ReceivedUnicastPackets = $_.ReceivedUnicastPackets
            SentUnicastPackets     = $_.SentUnicastPackets
        }
    })

    if (-not $rows.Count) {
        $perf = Get-CimInstance Win32_PerfRawData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue
        $rows = @($perf | ForEach-Object {
            [PSCustomObject]@{
                Name          = $_.Name
                ReceivedBytes = $_.BytesReceivedPersec
                SentBytes     = $_.BytesSentPersec
            }
        })
    }

    return New-ApiResult -Success $true -Message ("{0} interface stat(s)" -f $rows.Count) -Data @($rows)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
