# GetDnsInfo.ps1
try {
    $servers = @()
    try {
        $servers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses } |
            ForEach-Object {
                [PSCustomObject]@{
                    InterfaceAlias = $_.InterfaceAlias
                    Servers        = ($_.ServerAddresses -join ", ")
                }
            })
    }
    catch { }

    $suffix = $null
    try {
        $suffix = (Get-DnsClient -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ConnectionSpecificSuffix -First 1)
    }
    catch { }

    $hostsPath = $env:SystemRoot + "\System32\drivers\etc\hosts"
    $hostsExists = Test-Path -LiteralPath $hostsPath
    $entryCount = 0
    if ($hostsExists) {
        try {
            $lines = Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue
            $entryCount = @($lines | Where-Object { $_ -and $_ -notmatch '^\s*#' -and $_ -match '\S+\s+\S+' }).Count
        }
        catch { }
    }

    return New-ApiResult -Success $true -Message "DNS configuration" -Data ([PSCustomObject]@{
        DnsServers       = @($servers)
        ConnectionSuffix = $suffix
        HostsFilePath    = $hostsPath
        HostsFileExists  = $hostsExists
        HostsEntryCount  = $entryCount
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
