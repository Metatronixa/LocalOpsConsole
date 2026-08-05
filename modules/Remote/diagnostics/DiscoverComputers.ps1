try {
    $rows = @()

    # ARP / neighbor table (best effort — NetTCPIP may fail in some hosts)
    try {
        Import-Module NetTCPIP -ErrorAction SilentlyContinue | Out-Null
        Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and
                $_.IPAddress -notmatch '^(127\.|0\.|224\.|239\.|255\.)' -and
                $_.State -ne 'Unreachable'
            } |
            ForEach-Object {
                $ip = $_.IPAddress
                $rows += [PSCustomObject]@{
                    Name          = $ip
                    IPAddress     = $ip
                    MACAddress    = $_.LinkLayerAddress
                    Online        = ($_.State -eq 'Reachable' -or $_.State -eq 'Permanent')
                    NeighborState = [string]$_.State
                    Source        = "ARP/Neighbor"
                }
            }
    }
    catch {
        # Fallback: parse arp -a
        try {
            $arp = & arp.exe -a 2>$null | Out-String
            [regex]::Matches($arp, '(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F\-]{11,17})\s+(\w+)') | ForEach-Object {
                $ip = $_.Groups[1].Value
                if ($ip -match '^(127\.|0\.|224\.|239\.|255\.)') { return }
                $mac = $_.Groups[2].Value
                $type = $_.Groups[3].Value
                if (-not ($rows | Where-Object { $_.IPAddress -eq $ip })) {
                    $rows += [PSCustomObject]@{
                        Name          = $ip
                        IPAddress     = $ip
                        MACAddress    = $mac
                        Online        = ($type -match 'dynamic|static')
                        NeighborState = $type
                        Source        = "arp.exe"
                    }
                }
            }
        }
        catch { }
    }

    # Recent SMB connections (PCs you already talk to)
    try {
        Get-SmbConnection -ErrorAction SilentlyContinue | ForEach-Object {
            $server = $_.ServerName
            if (-not ($rows | Where-Object { $_.Name -eq $server -or $_.IPAddress -eq $server })) {
                $rows += [PSCustomObject]@{
                    Name          = $server
                    IPAddress     = $server
                    MACAddress    = $null
                    Online        = $true
                    NeighborState = "SMB"
                    Source        = "SmbConnection"
                }
            }
        }
    }
    catch { }

    $rows = @($rows | Sort-Object Name -Unique)
    return New-ApiResult -Success $true -Message ("{0} host(s) discovered" -f $rows.Count) -Data $rows
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
