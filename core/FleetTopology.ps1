# core/FleetTopology.ps1 - Fleet topology graph

function Get-LocFleetTopology {
    $agentsResult = Get-LocFleetAgents
    if (-not $agentsResult.Success) { return $agentsResult }

    $agents = @($agentsResult.Data)
    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    $hubIds = @{}

    $consoleIp = $null
    try { $consoleIp = Get-LocPreferredLanIPv4 } catch { Write-Debug $_.Exception.Message }
    $consoleGw = $null
    try {
        $gw = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' -and $_.NextHop } |
            Sort-Object RouteMetric |
            Select-Object -First 1
        if ($gw) { $consoleGw = [string]$gw.NextHop }
    }
    catch { Write-Debug $_.Exception.Message }

    $ensureHub = {
        param([string]$GatewayIp, [hashtable]$HubMap, [System.Collections.ArrayList]$NodeList)
        if ([string]::IsNullOrWhiteSpace($GatewayIp)) {
            $hid = "hub-lan"
            if (-not $HubMap.ContainsKey($hid)) {
                $HubMap[$hid] = $true
                [void]$NodeList.Add([PSCustomObject]@{
                    Id = $hid; Kind = "gateway"; Label = "LAN"; IPv4 = $null; Gateway = $null
                    Online = $true; UserName = $null; WindowsVersion = $null; AgentId = $null; MACAddress = $null
                    Source = $null; NeighborState = $null
                })
            }
            return $hid
        }
        $hid = "hub-$GatewayIp"
        if (-not $HubMap.ContainsKey($hid)) {
            $HubMap[$hid] = $true
            [void]$NodeList.Add([PSCustomObject]@{
                Id = $hid; Kind = "gateway"; Label = "GW $GatewayIp"; IPv4 = $GatewayIp; Gateway = $null
                Online = $true; UserName = $null; WindowsVersion = $null; AgentId = $null; MACAddress = $null
                Source = $null; NeighborState = $null
            })
        }
        return $hid
    }

    $consoleId = "console-host"
    [void]$nodes.Add([PSCustomObject]@{
        Id = $consoleId; Kind = "console"; Label = [string]$env:COMPUTERNAME
        IPv4 = $consoleIp; Gateway = $consoleGw; Online = $true
        UserName = $null; WindowsVersion = $null; AgentId = $null; MACAddress = $null
        Source = "console"; NeighborState = $null
    })

    $defaultHub = & $ensureHub -GatewayIp $consoleGw -HubMap $hubIds -NodeList $nodes
    [void]$edges.Add([PSCustomObject]@{ From = $consoleId; To = [string]$defaultHub; Kind = "uplink" })

    $agentIps = @{}
    $agentNames = @{}
    foreach ($a in $agents) {
        $aid = [string]$a.Id
        $id = "agent-$aid"
        $ip = [string]$a.IPv4
        $name = [string]$a.ComputerName
        if ($ip) { $agentIps[$ip.ToLowerInvariant()] = $true }
        if ($name) { $agentNames[$name.ToLowerInvariant()] = $true }
        $gw = [string]$a.Gateway
        $hub = if ($gw) { & $ensureHub -GatewayIp $gw -HubMap $hubIds -NodeList $nodes } else { [string]$defaultHub }
        $online = $false
        try { $online = [bool]$a.Online } catch { $online = $false }
        [void]$nodes.Add([PSCustomObject]@{
            Id = $id; Kind = "agent"
            Label = $(if ($name) { $name } else { $aid })
            IPv4 = $ip; Gateway = $gw; Online = $online
            UserName = [string]$a.UserName; WindowsVersion = [string]$a.WindowsVersion
            AgentId = $aid; MACAddress = $null
            Source = "fleet-agent"; NeighborState = $null
        })
        [void]$edges.Add([PSCustomObject]@{ From = $id; To = [string]$hub; Kind = "agent" })
    }

    $lanRows = @()
    try { $lanRows = @(Get-LocLanDiscoveryRows) } catch { $lanRows = @() }
    $lanCount = 0
    foreach ($r in $lanRows) {
        $ip = [string]$r.IPAddress
        $nm = [string]$r.Name
        if ($ip -and $agentIps.ContainsKey($ip.ToLowerInvariant())) { continue }
        if ($nm -and $agentNames.ContainsKey($nm.ToLowerInvariant())) { continue }
        if ($consoleIp -and $ip -eq $consoleIp) { continue }
        if ($consoleGw -and $ip -eq $consoleGw) { continue }
        if ($ip -match '\.255$' -or $ip -match '\.0$') { continue }
        $mac = [string]$r.MACAddress
        if ($mac -match '(?i)^ff[-:]ff[-:]ff[-:]ff[-:]ff[-:]ff$') { continue }
        $nid = if ($ip) { "lan-$($ip -replace '\.', '-')" } else { "lan-$([guid]::NewGuid().ToString('N').Substring(0, 8))" }
        $online = $false
        try { $online = [bool]$r.Online } catch { $online = $false }
        $src = if ($r.Source) { [string]$r.Source } else { "discovery" }
        $neigh = if ($r.NeighborState) { [string]$r.NeighborState } else { $null }
        [void]$nodes.Add([PSCustomObject]@{
            Id = $nid; Kind = "lan"
            Label = $(if ($nm -and $nm -ne $ip) { $nm } else { $ip })
            IPv4 = $ip; Gateway = $null; Online = $online
            UserName = $null; WindowsVersion = $null; AgentId = $null
            MACAddress = [string]$r.MACAddress
            Source = $src; NeighborState = $neigh
        })
        [void]$edges.Add([PSCustomObject]@{ From = $nid; To = [string]$defaultHub; Kind = "lan" })
        $lanCount++
    }

    $overrides = Get-LocDeviceTypeOverrides
    foreach ($node in @($nodes.ToArray())) {
        $inferred = Resolve-LocDeviceTypeInferred -Kind $node.Kind -Label $node.Label -IPv4 $node.IPv4
        $over = Get-LocDeviceTypeOverrideForNode -Overrides $overrides -NodeId $node.Id -MacAddress $node.MACAddress -IPv4 $node.IPv4
        $effective = if ($over) { $over } else { $inferred }
        $node | Add-Member -NotePropertyName DeviceType -NotePropertyValue $effective -Force
        $node | Add-Member -NotePropertyName DeviceTypeInferred -NotePropertyValue $inferred -Force
        $node | Add-Member -NotePropertyName DeviceTypeOverride -NotePropertyValue $over -Force
    }

    return New-ApiResult -Success $true -Message "Topology" -Data ([PSCustomObject]@{
        GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
        Agents      = @($agents).Count
        LanHosts    = $lanCount
        Nodes       = @($nodes.ToArray())
        Edges       = @($edges.ToArray())
    })
}

