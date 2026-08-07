# core/Fleet.ps1 - Fleet RMM business logic

$script:LocFleetCommandTypes = @(
    'RestartSpooler', 'FlushDns', 'RestartService', 'RunScript', 'Message',
    'CollectInventory', 'RestartComputer', 'GetServices', 'GetProcesses',
    'EndProcess', 'GetPrinters', 'NetHealthSmoke',
    'SfcScannow', 'ChkdskScan', 'ChkdskScheduleFix',
    'GetWindowsUpdateStatus', 'InstallWindowsUpdates',
    'GetRustDeskStatus', 'InstallRustDesk',
    'InstallPackage', 'GetEventLogTail', 'GetResourceOffenders',
    'SelfUpdate',
    'AuditSecurityBaseline', 'ApplySecurityPolicy'
)

function Get-LocFleetCommandTypes {
    return @($script:LocFleetCommandTypes)
}

function Get-LocFleetAgentRecord {
    param([string]$AgentId)

    $data = Get-LocFleetAgentsData
    $agents = $data.agents
    if ($agents -is [PSCustomObject]) {
        $prop = $agents.PSObject.Properties | Where-Object { $_.Name -eq $AgentId } | Select-Object -First 1
        if ($prop) { return $prop.Value }
    }
    elseif ($agents -is [hashtable] -and $agents.ContainsKey($AgentId)) {
        return $agents[$AgentId]
    }
    return $null
}

function ConvertTo-LocNullableDouble {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { return [double]$Value } catch { return $null }
}

function ConvertTo-LocNullableLong {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { return [int64]$Value } catch {
        try { return [int64][double]$Value } catch { return $null }
    }
}

function ConvertTo-LocNullableBool {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value -is [bool]) { return [bool]$Value }
    $s = [string]$Value
    if ($s -match '^(?i)true|1|yes$') { return $true }
    if ($s -match '^(?i)false|0|no$') { return $false }
    try { return [bool]$Value } catch { return $null }
}

function Get-LocFleetTelemetryValue {
    param(
        $Telemetry,
        [string]$Name
    )
    if ($null -eq $Telemetry) { return $null }
    if ($Telemetry -is [hashtable] -or $Telemetry -is [System.Collections.IDictionary]) {
        if ($Telemetry.ContainsKey($Name)) { return $Telemetry[$Name] }
        return $null
    }
    $prop = $Telemetry.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function ConvertTo-LocFleetAgentSummary {
    param(
        [Parameter(Mandatory)] $Agent,
        [int]$OfflineSeconds
    )

    try {
        $lastSeenRaw = $null
        if ($Agent.PSObject.Properties['LastSeen']) { $lastSeenRaw = $Agent.LastSeen }
        $lastSeen = [datetime]::MinValue
        if ($lastSeenRaw) {
            try { $lastSeen = [datetime]$lastSeenRaw } catch { $lastSeen = [datetime]::MinValue }
        }
        $online = ((Get-Date) - $lastSeen).TotalSeconds -le $OfflineSeconds
        $tel = $null
        if ($Agent.PSObject.Properties['Telemetry']) { $tel = $Agent.Telemetry }
        if (-not $tel) { $tel = @{} }

        $revoked = $false
        if ($Agent.PSObject.Properties['Revoked'] -and $null -ne $Agent.Revoked) {
            try { $revoked = [bool]$Agent.Revoked } catch { $revoked = $false }
        }

        # Prefer Int32-friendly uptime for JSON; keep full value when it fits
        $uptime = ConvertTo-LocNullableLong (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'UptimeSec')
        $cpuPct = ConvertTo-LocNullableDouble (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'CpuPct')
        $ramPct = ConvertTo-LocNullableDouble (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'RamPct')
        $spike = (($null -ne $cpuPct -and $cpuPct -ge 90) -or ($null -ne $ramPct -and $ramPct -ge 90))

        return [PSCustomObject]@{
            Id             = [string]$(if ($Agent.PSObject.Properties['Id']) { $Agent.Id } else { "" })
            ComputerName   = [string]$(if ($Agent.PSObject.Properties['ComputerName'] -and $Agent.ComputerName) { $Agent.ComputerName } else { "" })
            Online         = $online
            LastSeen       = if ($lastSeenRaw) { [string]$lastSeenRaw } else { $null }
            AgentVersion   = [string]$(if ($Agent.PSObject.Properties['AgentVersion'] -and $Agent.AgentVersion) { $Agent.AgentVersion } else { "" })
            Revoked        = $revoked
            CpuPct         = $cpuPct
            RamPct         = $ramPct
            DiskFreePct    = ConvertTo-LocNullableDouble (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'DiskFreePct')
            DiskReadMBps   = ConvertTo-LocNullableDouble (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'DiskReadMBps')
            DiskWriteMBps  = ConvertTo-LocNullableDouble (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'DiskWriteMBps')
            InternetOk     = ConvertTo-LocNullableBool (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'InternetOk')
            UserName       = [string]$(if (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'UserName') { Get-LocFleetTelemetryValue -Telemetry $tel -Name 'UserName' } else { "" })
            IPv4           = [string]$(if (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'IPv4') { Get-LocFleetTelemetryValue -Telemetry $tel -Name 'IPv4' } else { "" })
            Gateway        = [string]$(if (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'Gateway') { Get-LocFleetTelemetryValue -Telemetry $tel -Name 'Gateway' } else { "" })
            WindowsVersion = [string]$(if (Get-LocFleetTelemetryValue -Telemetry $tel -Name 'WindowsVersion') { Get-LocFleetTelemetryValue -Telemetry $tel -Name 'WindowsVersion' } else { "" })
            UptimeSec      = $uptime
            Inventory      = $(if ($Agent.PSObject.Properties['Inventory']) { $Agent.Inventory } else { $null })
            LastOffender   = $(if ($Agent.PSObject.Properties['LastOffender']) { $Agent.LastOffender } else { $null })
            SpikeActive    = [bool]$spike
        }
    }
    catch {
        $fallbackId = ""
        try { $fallbackId = [string]$Agent.Id } catch { }
        $fallbackName = ""
        try { $fallbackName = [string]$Agent.ComputerName } catch { }
        Write-LocLog -Module "FLEET" -Action "AgentSummary" -Level "ERROR" -Message "Summary failed for ${fallbackId}: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Id             = $fallbackId
            ComputerName   = $fallbackName
            Online         = $false
            LastSeen       = $null
            AgentVersion   = ""
            Revoked        = $false
            CpuPct         = $null
            RamPct         = $null
            DiskFreePct    = $null
            DiskReadMBps   = $null
            DiskWriteMBps  = $null
            InternetOk     = $null
            UserName       = ""
            IPv4           = ""
            Gateway        = ""
            WindowsVersion = ""
            UptimeSec      = $null
            Inventory      = $null
            LastOffender   = $null
            SpikeActive    = $false
        }
    }
}

function Enroll-LocAgent {
    param(
        [Parameter(Mandatory)] [string]$Token,
        [Parameter(Mandatory)] [string]$ComputerName,
        [string]$AgentVersion = "2.0.0"
    )

    if (-not (Test-LocFleetEnabled)) {
        return New-ApiResult -Success $false -Message "Fleet is disabled" -StatusCode 503
    }

    $settings = Get-LocSettings
    $expected = if ($settings.fleetEnrollToken) { [string]$settings.fleetEnrollToken } else { "" }
    if ([string]::IsNullOrWhiteSpace($expected) -or $Token -ne $expected) {
        Add-LocFleetAudit -Action "EnrollFailed" -Detail @{ ComputerName = $ComputerName }
        return New-ApiResult -Success $false -Message "Invalid enrollment token" -StatusCode 403
    }

    $agentId = [guid]::NewGuid().ToString("N")
    $secret = New-LocAgentSecret
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $record = [ordered]@{
        Id           = $agentId
        ComputerName = $ComputerName
        AgentVersion = $AgentVersion
        Secret       = $secret
        EnrolledAt   = $now
        LastSeen     = $now
        Revoked      = $false
        Telemetry    = @{}
        Inventory    = $null
    }

    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents) {
            if ($data.agents -is [PSCustomObject]) {
                foreach ($p in $data.agents.PSObject.Properties) {
                    $agentsHash[$p.Name] = $p.Value
                }
            }
            elseif ($data.agents -is [hashtable]) {
                $agentsHash = @{} + $data.agents
            }
        }
        $agentsHash[$agentId] = $record
        Write-LocFleetJson -FileName "agents.json" -Data @{ agents = $agentsHash }
    }

    Add-LocFleetAudit -Action "Enroll" -AgentId $agentId -Detail @{ ComputerName = $ComputerName; AgentVersion = $AgentVersion }
    Write-LocLog -Module "FLEET" -Action "Enroll" -Level "SUCCESS" -Message "Agent enrolled: $ComputerName ($agentId)"

    return New-ApiResult -Success $true -Message "Enrolled" -Data @{
        AgentId     = $agentId
        AgentSecret = $secret
    }
}

function Register-LocHeartbeat {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [hashtable]$Telemetry = @{}
    )

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent -or $agent.Revoked) {
        return New-ApiResult -Success $false -Message "Unknown or revoked agent" -StatusCode 403
    }

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) {
                $agentsHash[$p.Name] = $p.Value
            }
        }
        elseif ($data.agents -is [hashtable]) {
            $agentsHash = @{} + $data.agents
        }

        if (-not $agentsHash.ContainsKey($AgentId)) { return }

        $rec = $agentsHash[$AgentId]
        if ($rec -is [PSCustomObject]) {
            $rec | Add-Member -NotePropertyName LastSeen -NotePropertyValue $now -Force
            if ($Telemetry.ComputerName) { $rec | Add-Member -NotePropertyName ComputerName -NotePropertyValue $Telemetry.ComputerName -Force }
            if ($Telemetry.AgentVersion) { $rec | Add-Member -NotePropertyName AgentVersion -NotePropertyValue $Telemetry.AgentVersion -Force }
            $rec | Add-Member -NotePropertyName Telemetry -NotePropertyValue $Telemetry -Force
        }
        else {
            $rec.LastSeen = $now
            if ($Telemetry.ComputerName) { $rec.ComputerName = $Telemetry.ComputerName }
            if ($Telemetry.AgentVersion) { $rec.AgentVersion = $Telemetry.AgentVersion }
            $rec.Telemetry = $Telemetry
        }

        $agentsHash[$AgentId] = $rec
        Write-LocFleetJson -FileName "agents.json" -Data @{ agents = $agentsHash }
    }

    Evaluate-LocHeartbeatAlerts -AgentId $AgentId -Telemetry $Telemetry

    return New-ApiResult -Success $true -Message "Heartbeat recorded" -Data @{ LastSeen = $now }
}

function Get-LocFleetAgents {
    $offline = Get-LocFleetOfflineSeconds
    $data = Get-LocFleetAgentsData
    $list = New-Object System.Collections.Generic.List[object]

    try {
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) {
                try {
                    if ($p.Value -and -not $p.Value.Revoked) {
                        [void]$list.Add((ConvertTo-LocFleetAgentSummary -Agent $p.Value -OfflineSeconds $offline))
                    }
                }
                catch {
                    Write-LocLog -Module "FLEET" -Action "AgentsList" -Level "ERROR" -Message "Skip agent $($p.Name): $($_.Exception.Message)"
                }
            }
        }
        elseif ($data.agents -is [hashtable]) {
            foreach ($k in @($data.agents.Keys)) {
                try {
                    $a = $data.agents[$k]
                    if ($a -and -not $a.Revoked) {
                        [void]$list.Add((ConvertTo-LocFleetAgentSummary -Agent $a -OfflineSeconds $offline))
                    }
                }
                catch {
                    Write-LocLog -Module "FLEET" -Action "AgentsList" -Level "ERROR" -Message "Skip agent ${k}: $($_.Exception.Message)"
                }
            }
        }
    }
    catch {
        Write-LocLog -Module "FLEET" -Action "AgentsList" -Level "ERROR" -Message $_.Exception.Message
        return New-ApiResult -Success $false -Message "Failed to list agents: $($_.Exception.Message)" -StatusCode 500
    }

    $sorted = @($list | Sort-Object ComputerName)
    return New-ApiResult -Success $true -Message "Agents" -Data $sorted
}

function Get-LocLanDiscoveryRows {
    $rows = @()
    try {
        if (Get-Command Invoke-LocModuleAction -ErrorAction SilentlyContinue) {
            $disc = Invoke-LocModuleAction -ModuleId "remote" -Kind "diagnostics" -ActionName "DiscoverComputers" -ForceRefresh $true
            if ($disc -and $disc.Success -and $disc.Data) {
                return @($disc.Data)
            }
        }
    }
    catch { }

    try {
        Import-Module NetTCPIP -ErrorAction SilentlyContinue | Out-Null
        Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and
                $_.IPAddress -notmatch '^(127\.|0\.|224\.|239\.|255\.)' -and
                $_.State -ne 'Unreachable'
            } |
            ForEach-Object {
                $rows += [PSCustomObject]@{
                    Name          = $_.IPAddress
                    IPAddress     = $_.IPAddress
                    MACAddress    = $_.LinkLayerAddress
                    Online        = ($_.State -eq 'Reachable' -or $_.State -eq 'Permanent')
                    NeighborState = [string]$_.State
                    Source        = "ARP/Neighbor"
                }
            }
    }
    catch { }
    return @($rows)
}

function Get-LocFleetTopology {
    $agentsResult = Get-LocFleetAgents
    if (-not $agentsResult.Success) { return $agentsResult }

    $agents = @($agentsResult.Data)
    $nodes = New-Object System.Collections.ArrayList
    $edges = New-Object System.Collections.ArrayList
    $hubIds = @{}

    $consoleIp = $null
    try { $consoleIp = Get-LocPreferredLanIPv4 } catch { }
    $consoleGw = $null
    try {
        $gw = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' -and $_.NextHop } |
            Sort-Object RouteMetric |
            Select-Object -First 1
        if ($gw) { $consoleGw = [string]$gw.NextHop }
    }
    catch { }

    $ensureHub = {
        param([string]$GatewayIp, [hashtable]$HubMap, [System.Collections.ArrayList]$NodeList)
        if ([string]::IsNullOrWhiteSpace($GatewayIp)) {
            $hid = "hub-lan"
            if (-not $HubMap.ContainsKey($hid)) {
                $HubMap[$hid] = $true
                [void]$NodeList.Add([PSCustomObject]@{
                    Id = $hid; Kind = "gateway"; Label = "LAN"; IPv4 = $null; Gateway = $null
                    Online = $true; UserName = $null; WindowsVersion = $null; AgentId = $null; MACAddress = $null
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
            })
        }
        return $hid
    }

    $consoleId = "console-host"
    [void]$nodes.Add([PSCustomObject]@{
        Id = $consoleId; Kind = "console"; Label = [string]$env:COMPUTERNAME
        IPv4 = $consoleIp; Gateway = $consoleGw; Online = $true
        UserName = $null; WindowsVersion = $null; AgentId = $null; MACAddress = $null
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
        [void]$nodes.Add([PSCustomObject]@{
            Id = $nid; Kind = "lan"
            Label = $(if ($nm -and $nm -ne $ip) { $nm } else { $ip })
            IPv4 = $ip; Gateway = $null; Online = $online
            UserName = $null; WindowsVersion = $null; AgentId = $null
            MACAddress = [string]$r.MACAddress
        })
        [void]$edges.Add([PSCustomObject]@{ From = $nid; To = [string]$defaultHub; Kind = "lan" })
        $lanCount++
    }

    return New-ApiResult -Success $true -Message "Topology" -Data ([PSCustomObject]@{
        GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
        Agents      = @($agents).Count
        LanHosts    = $lanCount
        Nodes       = @($nodes.ToArray())
        Edges       = @($edges.ToArray())
    })
}

function Get-LocFleetAgentDetail {
    param([Parameter(Mandatory)] [string]$AgentId)

    try {
        $agent = Get-LocFleetAgentRecord -AgentId $AgentId
        if (-not $agent) {
            return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
        }

        $offline = Get-LocFleetOfflineSeconds
        $summary = ConvertTo-LocFleetAgentSummary -Agent $agent -OfflineSeconds $offline
        $cmds = @()
        $alerts = @()
        try { $cmds = @(Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 50) } catch { $cmds = @() }
        try { $alerts = @(Get-LocFleetAlertsForAgent -AgentId $AgentId -Limit 20) } catch { $alerts = @() }

        return New-ApiResult -Success $true -Message "Agent detail" -Data @{
            Agent    = $summary
            Commands = [System.Collections.ArrayList]@($cmds)
            Alerts   = [System.Collections.ArrayList]@($alerts)
        }
    }
    catch {
        Write-LocLog -Module "FLEET" -Action "AgentDetail" -Level "ERROR" -Message "Agent ${AgentId}: $($_.Exception.Message)"
        return New-ApiResult -Success $false -Message "Failed to load agent: $($_.Exception.Message)" -StatusCode 500
    }
}

function Test-LocFleetAgentLatency {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [string]$TargetHost = ""
    )

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent -or $agent.Revoked) {
        return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
    }

    $hostName = $TargetHost
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        if ($agent.Telemetry -and $agent.Telemetry.IPv4) {
            $hostName = [string]$agent.Telemetry.IPv4
        }
    }
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        return New-ApiResult -Success $false -Message "No agent IPv4 in telemetry - wait for a heartbeat or pass TargetHost" -StatusCode 400
    }

    $rtt = New-Object System.Collections.Generic.List[double]
    $ok = $false
    $errorMsg = ""
    try {
        $pings = Test-Connection -ComputerName $hostName -Count 3 -ErrorAction Stop
        foreach ($p in @($pings)) {
            $ms = $null
            if ($null -ne $p.ResponseTime) { $ms = [double]$p.ResponseTime }
            elseif ($null -ne $p.Latency) { $ms = [double]$p.Latency }
            if ($null -ne $ms) { [void]$rtt.Add($ms) }
        }
        $ok = $rtt.Count -gt 0
        if (-not $ok) { $errorMsg = "Ping returned no RTT samples (ICMP may be blocked)" }
    }
    catch {
        $errorMsg = $_.Exception.Message
        try {
            $tnc = Test-NetConnection -ComputerName $hostName -WarningAction SilentlyContinue -ErrorAction Stop
            if ($tnc -and $tnc.PingSucceeded -and $null -ne $tnc.PingReplyDetails -and $null -ne $tnc.PingReplyDetails.RoundtripTime) {
                [void]$rtt.Add([double]$tnc.PingReplyDetails.RoundtripTime)
                $ok = $true
                $errorMsg = ""
            }
            elseif (-not $errorMsg) {
                $errorMsg = "Ping unsuccessful to $hostName"
            }
        }
        catch {
            if (-not $errorMsg) { $errorMsg = $_.Exception.Message }
        }
    }

    $avg = $null
    $min = $null
    $max = $null
    if ($rtt.Count -gt 0) {
        $avg = [math]::Round((($rtt | Measure-Object -Average).Average), 1)
        $min = [math]::Round((($rtt | Measure-Object -Minimum).Minimum), 1)
        $max = [math]::Round((($rtt | Measure-Object -Maximum).Maximum), 1)
    }

    $probeOk = [bool]$ok
    $msg = if ($probeOk) { "Latency to $hostName" } else { "Latency probe failed: $errorMsg" }
    $payload = [ordered]@{
        TargetHost = $hostName
        ProbeOk    = $probeOk
        AvgMs      = $avg
        MinMs      = $min
        MaxMs      = $max
        Samples    = @($rtt.ToArray())
        Error      = $errorMsg
        ProbedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    # Always Success=true when the endpoint works; ProbeOk says whether ICMP succeeded (avoids UI API WARN spam).
    return New-ApiResult -Success $true -Message $msg -Data $payload
}

function Queue-LocFleetCommand {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] [string]$Type,
        [object]$Payload = $null
    )

    if ($script:LocFleetCommandTypes -notcontains $Type) {
        return New-ApiResult -Success $false -Message "Invalid command type: $Type" -StatusCode 400
    }

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent -or $agent.Revoked) {
        return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
    }

    $payloadHash = @{}
    if ($null -ne $Payload) {
        if ($Payload -is [hashtable]) {
            $payloadHash = @{} + $Payload
        }
        elseif ($Payload -is [PSCustomObject]) {
            foreach ($p in $Payload.PSObject.Properties) { $payloadHash[$p.Name] = $p.Value }
        }
    }

    if ($Type -eq 'InstallPackage') {
        $pkgId = if ($payloadHash.PackageId) { [string]$payloadHash.PackageId } else { '' }
        if ([string]::IsNullOrWhiteSpace($pkgId)) {
            return New-ApiResult -Success $false -Message 'PackageId required' -StatusCode 400
        }
        $pkg = Get-LocFleetPackageById -PackageId $pkgId
        if (-not $pkg) {
            return New-ApiResult -Success $false -Message "Unknown package: $pkgId" -StatusCode 400
        }
        $payloadHash.PackageId = [string]$pkg.Id
        $payloadHash.Name = [string]$pkg.Name
        if ($pkg.WingetId) { $payloadHash.WingetId = [string]$pkg.WingetId }
        if ($pkg.Url) { $payloadHash.Url = [string]$pkg.Url }
        if ($pkg.SilentArgs) { $payloadHash.SilentArgs = [string]$pkg.SilentArgs }
        if ($pkg.Sha256) { $payloadHash.Sha256 = [string]$pkg.Sha256 }
    }

    if ($Type -eq 'ApplySecurityPolicy') {
        $packId = if ($payloadHash.PackId) { [string]$payloadHash.PackId } else { 'hardening-basic' }
        $pack = Get-LocFleetPolicyPackById -PackId $packId
        if (-not $pack) {
            return New-ApiResult -Success $false -Message "Unknown policy pack: $packId" -StatusCode 400
        }
        $payloadHash.PackId = [string]$pack.id
        $payloadHash.PackName = [string]$pack.name
        $payloadHash.PackVersion = [string]$pack.version
        $payloadHash.ControlIds = @($pack.controls | ForEach-Object { [string]$_.id })
    }

    if ($Type -eq 'InstallRustDesk') {
        try {
            $settings = Get-LocSettings
            $url = if ($settings.PSObject.Properties['rustDeskInstallerUrl']) { [string]$settings.rustDeskInstallerUrl } else { '' }
            $sha = if ($settings.PSObject.Properties['rustDeskInstallerSha256']) { [string]$settings.rustDeskInstallerSha256 } else { '' }
            $silent = if ($settings.PSObject.Properties['rustDeskSilentArgs']) { [string]$settings.rustDeskSilentArgs } else { '/S' }
            if ([string]::IsNullOrWhiteSpace($url)) {
                return New-ApiResult -Success $false -Message 'rustDeskInstallerUrl is not set in settings.json' -StatusCode 400
            }
            if ($url -notmatch '^https://') {
                return New-ApiResult -Success $false -Message 'rustDeskInstallerUrl must be HTTPS' -StatusCode 400
            }
            $payloadHash.InstallerUrl = $url.Trim()
            if (-not [string]::IsNullOrWhiteSpace($sha)) { $payloadHash.InstallerSha256 = $sha.Trim() }
            if ([string]::IsNullOrWhiteSpace($silent)) { $silent = '/S' }
            $payloadHash.SilentArgs = $silent.Trim()
        }
        catch {
            return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
        }
    }

    $cmdId = [guid]::NewGuid().ToString("N")
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $cmd = [ordered]@{
        Id          = $cmdId
        AgentId     = $AgentId
        Type        = $Type
        Payload     = $payloadHash
        Status      = "Pending"
        CreatedAt   = $now
        ClaimedAt   = $null
        CompletedAt = $null
        Result      = $null
    }

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $data = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($data.commands) { $list = @($data.commands) }
        $list += $cmd
        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    Add-LocFleetAudit -Action "CommandQueued" -AgentId $AgentId -Detail @{ CommandId = $cmdId; Type = $Type; Payload = $Payload }
    Write-LocLog -Module "FLEET" -Action "QueueCommand" -Level "INFO" -Message "$Type queued for $AgentId ($cmdId)"

    return New-ApiResult -Success $true -Message "Command queued" -Data $cmd
}

# Running jobs older than this are treated as abandoned (agent never posted a result).
$script:LocFleetRunningTimeoutMinutes = 45

function Test-LocFleetCommandStaleRunning {
    param(
        [object]$Command,
        [datetime]$Now = $(Get-Date),
        [int]$TimeoutMinutes = 0
    )
    if (-not $Command) { return $false }
    if ([string]$Command.Status -ne "Running") { return $false }
    if ($TimeoutMinutes -lt 1) { $TimeoutMinutes = [int]$script:LocFleetRunningTimeoutMinutes }
    $claimedRaw = [string]$Command.ClaimedAt
    if ([string]::IsNullOrWhiteSpace($claimedRaw)) {
        $claimedRaw = [string]$Command.CreatedAt
    }
    $claimedAt = $null
    if (-not [datetime]::TryParse($claimedRaw, [ref]$claimedAt)) { return $false }
    return (($Now - $claimedAt).TotalMinutes -ge $TimeoutMinutes)
}

function Cancel-LocFleetCommand {
    param(
        [Parameter(Mandatory)] [string]$CommandId,
        [string]$AgentId = "",
        [string]$Reason = "Cancelled by operator"
    )

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $found = $false
    $updated = $null

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $store = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($store.commands) { $list = @($store.commands) }

        for ($i = 0; $i -lt $list.Count; $i++) {
            $c = $list[$i]
            if ([string]$c.Id -ne $CommandId) { continue }
            if ($AgentId -and [string]$c.AgentId -ne $AgentId) { continue }
            $status = [string]$c.Status
            if ($status -notin @('Pending', 'Running')) {
                $updated = $c
                $found = $true
                break
            }
            $c.Status = "Failed"
            $c.CompletedAt = $now
            $c.Result = [ordered]@{
                Success    = $false
                Message    = $Reason
                Data       = $null
                ExitCode   = -1
                DurationMs = 0
                LogLines   = @()
            }
            $list[$i] = $c
            $updated = $c
            $found = $true
            break
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    if (-not $found) {
        return New-ApiResult -Success $false -Message "Command not found" -StatusCode 404
    }

    Add-LocFleetAudit -Action "CommandCancelled" -AgentId ([string]$updated.AgentId) -Detail @{
        CommandId = $CommandId
        Type      = [string]$updated.Type
        Reason    = $Reason
    }
    Write-LocLog -Module "FLEET" -Action "CancelCommand" -Level "WARN" -Message "Cancelled $CommandId ($Reason)"
    return New-ApiResult -Success $true -Message "Command cancelled" -Data $updated
}

function Cancel-LocFleetStuckCommands {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [string]$Reason = "Cleared stuck Running/Pending by operator"
    )

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent) {
        return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
    }

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $cleared = New-Object System.Collections.ArrayList

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $store = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($store.commands) { $list = @($store.commands) }

        for ($i = 0; $i -lt $list.Count; $i++) {
            $c = $list[$i]
            if ([string]$c.AgentId -ne $AgentId) { continue }
            if ([string]$c.Status -notin @('Pending', 'Running')) { continue }
            $c.Status = "Failed"
            $c.CompletedAt = $now
            $c.Result = [ordered]@{
                Success    = $false
                Message    = $Reason
                Data       = $null
                ExitCode   = -1
                DurationMs = 0
                LogLines   = @()
            }
            $list[$i] = $c
            [void]$cleared.Add([PSCustomObject]@{ Id = $c.Id; Type = $c.Type })
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    Add-LocFleetAudit -Action "StuckCommandsCleared" -AgentId $AgentId -Detail @{
        Count  = $cleared.Count
        Reason = $Reason
        Items  = @($cleared.ToArray())
    }
    return New-ApiResult -Success $true -Message ("Cleared {0} stuck command(s)" -f $cleared.Count) -Data @{
        Cleared = @($cleared.ToArray())
        Count   = $cleared.Count
    }
}

function Claim-LocFleetCommands {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [int]$MaxClaim = 1
    )

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent -or $agent.Revoked) {
        return New-ApiResult -Success $false -Message "Unknown or revoked agent" -StatusCode 403
    }

    if ($MaxClaim -lt 1) { $MaxClaim = 1 }

    # ArrayList so Add() works inside the lock scriptblock (+= would create a local copy).
    $claimedList = New-Object System.Collections.ArrayList
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $utcNow = Get-Date

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $data = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($data.commands) { $list = @($data.commands) }

        # Expire abandoned Running jobs so Pending work can proceed.
        for ($i = 0; $i -lt $list.Count; $i++) {
            $c = $list[$i]
            if ([string]$c.AgentId -ne $AgentId) { continue }
            if (-not (Test-LocFleetCommandStaleRunning -Command $c -Now $utcNow)) { continue }
            $c.Status = "Failed"
            $c.CompletedAt = $now
            $c.Result = [ordered]@{
                Success    = $false
                Message    = ("Timed out - agent never reported result (Running > {0}m)" -f $script:LocFleetRunningTimeoutMinutes)
                Data       = $null
                ExitCode   = -1
                DurationMs = 0
                LogLines   = @()
            }
            $list[$i] = $c
            Write-LocLog -Module "FLEET" -Action "Claim" -Level "WARN" -Message "Expired stale Running $($c.Id) ($($c.Type))"
        }

        # Do not pile up Running jobs while a long command (e.g. SFC) is in flight.
        $hasRunning = $false
        foreach ($c in $list) {
            if ([string]$c.AgentId -eq $AgentId -and [string]$c.Status -eq "Running") {
                $hasRunning = $true
                break
            }
        }
        if ($hasRunning) {
            Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
            return
        }

        $taken = 0
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($taken -ge $MaxClaim) { break }
            $c = $list[$i]
            if ([string]$c.AgentId -eq $AgentId -and [string]$c.Status -eq "Pending") {
                $c.Status = "Running"
                $c.ClaimedAt = $now
                $list[$i] = $c
                [void]$claimedList.Add([PSCustomObject]@{
                    Id      = $c.Id
                    Type    = $c.Type
                    Payload = $c.Payload
                })
                $taken++
            }
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    return New-ApiResult -Success $true -Message "Poll" -Data @($claimedList.ToArray())
}

function Complete-LocFleetCommand {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] [string]$CommandId,
        [bool]$Success = $true,
        [string]$Message = "",
        [object]$Data = $null,
        [int]$ExitCode = 0,
        [int]$DurationMs = 0,
        [object[]]$LogLines = @()
    )

    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $found = $false

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $store = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($store.commands) { $list = @($store.commands) }

        for ($i = 0; $i -lt $list.Count; $i++) {
            $c = $list[$i]
            if ([string]$c.Id -eq $CommandId -and [string]$c.AgentId -eq $AgentId) {
                $c.Status = if ($Success) { "Completed" } else { "Failed" }
                $c.CompletedAt = $now
                $c.Result = [ordered]@{
                    Success    = $Success
                    Message    = $Message
                    Data       = $Data
                    ExitCode   = $ExitCode
                    DurationMs = $DurationMs
                    LogLines   = @($LogLines)
                }
                $list[$i] = $c
                $found = $true

                if ($c.Type -eq "CollectInventory" -and $Success -and $Data) {
                    Update-LocFleetAgentInventory -AgentId $AgentId -Inventory $Data
                }
                break
            }
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    if (-not $found) {
        return New-ApiResult -Success $false -Message "Command not found" -StatusCode 404
    }

    if ($Success -and $Data) {
        $cmdType = $null
        try {
            $all = Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 50
            $match = @($all | Where-Object { [string]$_.Id -eq $CommandId } | Select-Object -First 1)
            if ($match) { $cmdType = [string]$match[0].Type }
        }
        catch { }
        if ($cmdType -eq 'GetResourceOffenders') {
            try { Update-LocFleetAgentLastOffender -AgentId $AgentId -Offender $Data } catch { }
            try { Enrich-LocFleetSpikeFromOffenders -AgentId $AgentId -Data $Data } catch { }
        }
    }

    Add-LocFleetAudit -Action "CommandResult" -AgentId $AgentId -Detail @{
        CommandId  = $CommandId
        Success    = $Success
        Message    = $Message
        ExitCode   = $ExitCode
        DurationMs = $DurationMs
    }

    return New-ApiResult -Success $true -Message "Result recorded" -Data @{ CommandId = $CommandId }
}

function Update-LocFleetAgentLastOffender {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] $Offender
    )

    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) { $agentsHash[$p.Name] = $p.Value }
        }
        elseif ($data.agents -is [hashtable]) { $agentsHash = @{} + $data.agents }

        if ($agentsHash.ContainsKey($AgentId)) {
            $rec = $agentsHash[$AgentId]
            $top = $null
            try {
                if ($Offender.TopProcesses) {
                    $list = @($Offender.TopProcesses)
                    if ($list.Count -gt 0) { $top = $list[0] }
                }
            }
            catch { }
            $payload = [ordered]@{
                CapturedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                TopProcess   = $top
                RelatedService = $(if ($Offender.RelatedService) { $Offender.RelatedService } else { $null })
                Summary      = $(if ($Offender.Summary) { [string]$Offender.Summary } else { '' })
            }
            if ($rec -is [PSCustomObject]) {
                $rec | Add-Member -NotePropertyName LastOffender -NotePropertyValue $payload -Force
            }
            else { $rec.LastOffender = $payload }
            $agentsHash[$AgentId] = $rec
            Write-LocFleetJson -FileName "agents.json" -Data @{ agents = $agentsHash }
        }
    }
}

function Update-LocFleetAgentInventory {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] $Inventory
    )

    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) { $agentsHash[$p.Name] = $p.Value }
        }
        elseif ($data.agents -is [hashtable]) { $agentsHash = @{} + $data.agents }

        if ($agentsHash.ContainsKey($AgentId)) {
            $rec = $agentsHash[$AgentId]
            if ($rec -is [PSCustomObject]) {
                $rec | Add-Member -NotePropertyName Inventory -NotePropertyValue $Inventory -Force
            }
            else { $rec.Inventory = $Inventory }
            $agentsHash[$AgentId] = $rec
            Write-LocFleetJson -FileName "agents.json" -Data @{ agents = $agentsHash }
        }
    }
}

function Get-LocFleetCommandsForAgent {
    param(
        [string]$AgentId = "",
        [int]$Limit = 100
    )

    $data = Get-LocFleetCommandsData
    $list = @()
    if ($data.commands) { $list = @($data.commands) }

    if ($AgentId) {
        $list = @($list | Where-Object { [string]$_.AgentId -eq $AgentId })
    }

    return @($list | Sort-Object { [datetime]$_.CreatedAt } -Descending | Select-Object -First $Limit)
}

function Get-LocFleetCommands {
    param([string]$AgentId = "")

    $cmds = Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 100
    return New-ApiResult -Success $true -Message "Commands" -Data @($cmds)
}

function Get-LocFleetAlertsForAgent {
    param(
        [string]$AgentId = "",
        [int]$Limit = 50
    )

    $data = Get-LocFleetAlertsData
    $list = @()
    if ($data.alerts) { $list = @($data.alerts) }
    if ($AgentId) {
        $list = @($list | Where-Object { [string]$_.AgentId -eq $AgentId })
    }
    return @($list | Sort-Object { [datetime]$_.CreatedAt } -Descending | Select-Object -First $Limit)
}

function Get-LocFleetAlerts {
    $alerts = Get-LocFleetAlertsForAgent -Limit 200
    return New-ApiResult -Success $true -Message "Alerts" -Data @($alerts)
}

function Add-LocFleetAlert {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] [string]$Type,
        [string]$Message = "",
        [object]$Detail = $null
    )

    $alert = [ordered]@{
        Id        = [guid]::NewGuid().ToString("N")
        AgentId   = $AgentId
        Type      = $Type
        Message   = $Message
        Detail    = $Detail
        CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Acked     = $false
    }

    Invoke-LocFleetFileLock -Name "alerts" -Action {
        $data = Read-LocFleetJson -FileName "alerts.json" -Default @{ alerts = @() }
        $list = @()
        if ($data.alerts) { $list = @($data.alerts) }
        $list += $alert
        Write-LocFleetJson -FileName "alerts.json" -Data @{ alerts = $list }
    }

    return $alert
}

function Evaluate-LocHeartbeatAlerts {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [hashtable]$Telemetry = @{}
    )

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    $pcName = if ($agent -and $agent.ComputerName) { [string]$agent.ComputerName } else { $AgentId }
    $cpu = ConvertTo-LocNullableDouble $Telemetry.CpuPct
    $ram = ConvertTo-LocNullableDouble $Telemetry.RamPct
    $disk = ConvertTo-LocNullableDouble $Telemetry.DiskFreePct

    $spike = $false
    if ($null -ne $cpu -and $cpu -ge 90) {
        if (-not (Test-LocFleetAlertRecently -AgentId $AgentId -Type 'HighCpu' -WindowSec 300)) {
            $alert = Add-LocFleetAlert -AgentId $AgentId -Type "HighCpu" -Message ("{0}: CPU at {1}%" -f $pcName, $cpu) -Detail @{ CpuPct = $cpu; ComputerName = $pcName }
            Publish-LocFleetSpikeAlert -AgentId $AgentId -ComputerName $pcName -Type "HighCpu" -Message $alert.Message -Detail $alert.Detail
        }
        $spike = $true
    }
    if ($null -ne $ram -and $ram -ge 90) {
        if (-not (Test-LocFleetAlertRecently -AgentId $AgentId -Type 'HighRam' -WindowSec 300)) {
            $alert = Add-LocFleetAlert -AgentId $AgentId -Type "HighRam" -Message ("{0}: RAM at {1}%" -f $pcName, $ram) -Detail @{ RamPct = $ram; ComputerName = $pcName }
            Publish-LocFleetSpikeAlert -AgentId $AgentId -ComputerName $pcName -Type "HighRam" -Message $alert.Message -Detail $alert.Detail
        }
        $spike = $true
    }
    if ($null -ne $disk -and $disk -lt 10) {
        if (-not (Test-LocFleetAlertRecently -AgentId $AgentId -Type 'LowDisk' -WindowSec 900)) {
            Add-LocFleetAlert -AgentId $AgentId -Type "LowDisk" -Message ("{0}: Disk free {1}%" -f $pcName, $disk) -Detail @{ DiskFreePct = $disk; ComputerName = $pcName }
        }
    }

    if ($spike) {
        try {
            $recent = @(Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 15)
            $busy = $false
            foreach ($c in $recent) {
                if ([string]$c.Type -ne 'GetResourceOffenders') { continue }
                if ($c.Status -in @('Pending', 'Running')) { $busy = $true; break }
                if ($c.Status -eq 'Completed' -and $c.CompletedAt) {
                    try {
                        if (((Get-Date) - [datetime]$c.CompletedAt).TotalSeconds -lt 300) { $busy = $true; break }
                    }
                    catch { }
                }
            }
            if (-not $busy) {
                Queue-LocFleetCommand -AgentId $AgentId -Type 'GetResourceOffenders' -Payload @{ Top = 8 } | Out-Null
            }
        }
        catch { }
    }
}

function Test-LocFleetAlertRecently {
    param(
        [string]$AgentId,
        [string]$Type,
        [int]$WindowSec = 300
    )
    $alerts = @(Get-LocFleetAlertsForAgent -AgentId $AgentId -Limit 30)
    foreach ($a in $alerts) {
        if ([string]$a.Type -ne $Type) { continue }
        try {
            if (((Get-Date) - [datetime]$a.CreatedAt).TotalSeconds -lt $WindowSec) { return $true }
        }
        catch { }
    }
    return $false
}

function Publish-LocFleetSpikeAlert {
    param(
        [string]$AgentId,
        [string]$ComputerName,
        [string]$Type,
        [string]$Message,
        [object]$Detail = $null
    )
    try {
        $fixedTitle = "Fleet {0}: {1}" -f $Type, $ComputerName
        if (Get-Command New-LocIncident -ErrorAction SilentlyContinue) {
            $inc = New-LocIncident -Title $fixedTitle -Category 'fleet' -Severity 'Warning' -Score 65 `
                -CorrelationKey ("fleet|{0}|{1}" -f $AgentId, $Type) `
                -Event @{ Message = $Message; AgentId = $AgentId; Detail = $Detail; Source = 'Fleet' }
            if (Get-Command Invoke-LocIncidentNotify -ErrorAction SilentlyContinue) {
                Invoke-LocIncidentNotify -Incident $inc -IsNew $true
            }
        }
        elseif (Get-Command Add-LocAlert -ErrorAction SilentlyContinue) {
            Add-LocAlert -Alert ([PSCustomObject]@{
                Id           = [guid]::NewGuid().ToString('N')
                Title        = $fixedTitle
                Message      = $Message
                Severity     = 'Warning'
                Category     = 'fleet'
                Source       = 'Fleet'
                ComputerName = $ComputerName
                AgentId      = $AgentId
                Type         = $Type
                Detail       = $Detail
                Acknowledged = $false
                Timestamp    = (Get-Date).ToUniversalTime().ToString('o')
            })
        }
        Write-LocLog -Module 'FLEET' -Action 'SpikeAlert' -Level 'WARN' -Message $Message
    }
    catch {
        Write-LocLog -Module 'FLEET' -Action 'SpikeAlert' -Level 'ERROR' -Message $_.Exception.Message
    }
}

function Enrich-LocFleetSpikeFromOffenders {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] $Data
    )

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    $pcName = if ($agent -and $agent.ComputerName) { [string]$agent.ComputerName } else { $AgentId }
    $topName = ''
    $topPid = $null
    $svcName = ''
    try {
        $procs = @($Data.TopProcesses)
        if ($procs.Count -gt 0) {
            $top = $procs[0]
            $topName = [string]$(if ($top.Name) { $top.Name } elseif ($top.ProcessName) { $top.ProcessName } else { '' })
            $topPid = if ($null -ne $top.Id) { $top.Id } elseif ($null -ne $top.ProcessId) { $top.ProcessId } else { $null }
        }
        if ($Data.RelatedService) {
            $svcName = [string]$(if ($Data.RelatedService.Name) { $Data.RelatedService.Name } else { $Data.RelatedService })
        }
    }
    catch { }

    $msg = "{0}: top offender {1}" -f $pcName, $(if ($topName) { $topName } else { 'unknown' })
    if ($null -ne $topPid) { $msg += " (PID $topPid)" }
    if ($svcName) { $msg += " · service $svcName" }

    Add-LocFleetAlert -AgentId $AgentId -Type 'ResourceOffenders' -Message $msg -Detail @{
        ComputerName   = $pcName
        TopProcessName = $topName
        TopProcessId   = $topPid
        RelatedService = $svcName
        Offenders      = $Data
    }

    if (Get-Command Add-LocAlert -ErrorAction SilentlyContinue) {
        Add-LocAlert -Alert ([PSCustomObject]@{
            Id           = [guid]::NewGuid().ToString('N')
            Title        = "Fleet offender: $pcName"
            Message      = $msg
            Severity     = 'Warning'
            Category     = 'fleet'
            Source       = 'Fleet'
            ComputerName = $pcName
            AgentId      = $AgentId
            Type         = 'ResourceOffenders'
            Detail       = $Data
            Acknowledged = $false
            Timestamp    = (Get-Date).ToUniversalTime().ToString('o')
        })
    }
    Write-LocLog -Module 'FLEET' -Action 'OffenderEnrich' -Level 'WARN' -Message $msg
}

function Get-LocFleetPolicyPackDir {
    return (Join-Path (Get-LocRoot) "data\fleet\policy-packs")
}

function Get-LocFleetPolicyPackById {
    param([Parameter(Mandatory)] [string]$PackId)
    $dir = Get-LocFleetPolicyPackDir
    $path = Join-Path $dir ("{0}.json" -f $PackId)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-LocFleetPolicyPacks {
    $dir = Get-LocFleetPolicyPackDir
    $list = @()
    if (Test-Path -LiteralPath $dir) {
        Get-ChildItem -Path $dir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($p -and $p.id) {
                    $list += [PSCustomObject]@{
                        Id          = [string]$p.id
                        Name        = [string]$p.name
                        Version     = [string]$p.version
                        Description = [string]$p.description
                        Controls    = @($p.controls)
                    }
                }
            }
            catch { }
        }
    }
    return New-ApiResult -Success $true -Message "Policy packs" -Data @($list)
}

function Get-LocFleetPackages {
    $path = Join-Path (Get-LocFleetDir) 'packages.json'
    if (-not (Test-Path $path)) {
        $seed = @{
            packages = @(
                @{ Id = 'chrome'; Name = 'Google Chrome'; WingetId = 'Google.Chrome'; Category = 'Browser' }
                @{ Id = 'edge'; Name = 'Microsoft Edge'; WingetId = 'Microsoft.Edge'; Category = 'Browser' }
                @{ Id = 'firefox'; Name = 'Mozilla Firefox'; WingetId = 'Mozilla.Firefox'; Category = 'Browser' }
                @{ Id = 'adobe-reader'; Name = 'Adobe Acrobat Reader'; WingetId = 'Adobe.Acrobat.Reader.64-bit'; Category = 'Productivity' }
                @{ Id = '7zip'; Name = '7-Zip'; WingetId = '7zip.7zip'; Category = 'Utility' }
                @{ Id = 'vcredist'; Name = 'Visual C++ Redistributable 2015-2022'; WingetId = 'Microsoft.VCRedist.2015+.x64'; Category = 'Runtime' }
            )
        }
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ($seed | ConvertTo-Json -Depth 6) | Set-Content -Path $path -Encoding UTF8
    }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $list = @()
        if ($raw.packages) { $list = @($raw.packages) }
        return New-ApiResult -Success $true -Message 'Packages' -Data @($list)
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

function Get-LocFleetPackageById {
    param([Parameter(Mandatory)][string]$PackageId)
    $res = Get-LocFleetPackages
    if (-not $res.Success) { return $null }
    return @($res.Data) | Where-Object { [string]$_.Id -eq $PackageId } | Select-Object -First 1
}

function Revoke-LocAgent {
    param([Parameter(Mandatory)] [string]$AgentId)

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent) {
        return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
    }

    # Hard-remove so the PC disappears from Computers (soft Revoked flag alone was easy to miss).
    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) { $agentsHash[$p.Name] = $p.Value }
        }
        elseif ($data.agents -is [hashtable]) { $agentsHash = @{} + $data.agents }

        if ($agentsHash.ContainsKey($AgentId)) {
            $agentsHash.Remove($AgentId)
            Write-LocFleetJson -FileName "agents.json" -Data @{ agents = $agentsHash }
        }
    }

    Add-LocFleetAudit -Action "AgentRevoked" -AgentId $AgentId
    return New-ApiResult -Success $true -Message "Agent removed" -Data @{ AgentId = $AgentId }
}

function Rotate-LocFleetEnrollToken {
    $token = New-LocEnrollmentToken
    $root = Get-LocRoot
    $settingsPath = Join-Path $root "settings.json"
    $settingsObj = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $settingsObj | Add-Member -NotePropertyName fleetEnrollToken -NotePropertyValue $token -Force
    ($settingsObj | ConvertTo-Json -Depth 5) | Set-Content $settingsPath -Encoding UTF8
    Initialize-LocSettings -RootPath $root

    Write-LocFleetJson -FileName "meta.json" -Data @{
        enrollToken = $token
        updatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    Add-LocFleetAudit -Action "EnrollTokenRotated"
    return New-ApiResult -Success $true -Message "Enrollment token rotated" -Data @{ Token = $token }
}

function Get-LocPreferredLanIPv4 {
    try {
        $nic = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -and (@($_.IPAddress) | Where-Object {
                    $_ -match '^\d+\.\d+\.\d+\.\d+$' -and
                    $_ -notmatch '^127\.' -and
                    $_ -notmatch '^169\.254\.'
                })
            } |
            Select-Object -First 1
        if (-not $nic) { return "" }
        $ipv4 = @($nic.IPAddress) | Where-Object {
            $_ -match '^\d+\.\d+\.\d+\.\d+$' -and
            $_ -notmatch '^127\.' -and
            $_ -notmatch '^169\.254\.'
        } | Select-Object -First 1
        if ($ipv4) { return [string]$ipv4 }
    }
    catch { }
    return ""
}

function Get-LocFleetSuggestedServerUrl {
    param(
        [string]$PublicUrl = "",
        [string]$BindHost = "localhost",
        [int]$Port = 8787
    )

    $bind = if ($BindHost) { $BindHost.Trim() } else { "localhost" }
    $isLoopback = $bind -match '^(?i)(localhost|127\.0\.0\.1|::1)$'
    $isWildcard = $bind -match '^(?i)(0\.0\.0\.0|\+|\[::\])$'
    $lanIp = Get-LocPreferredLanIPv4
    $allowsRemote = -not $isLoopback

    if ($PublicUrl -and $PublicUrl.Trim()) {
        return [PSCustomObject]@{
            SuggestedUrl  = $PublicUrl.Trim().TrimEnd('/')
            DetectedLanIp = $lanIp
            BindHost      = $bind
            AllowsRemote  = $allowsRemote
            Source        = "fleetPublicUrl"
        }
    }

    if (-not $isLoopback -and -not $isWildcard) {
        return [PSCustomObject]@{
            SuggestedUrl  = "http://${bind}:$Port"
            DetectedLanIp = $lanIp
            BindHost      = $bind
            AllowsRemote  = $true
            Source        = "bindHost"
        }
    }

    if ($lanIp) {
        return [PSCustomObject]@{
            SuggestedUrl  = "http://${lanIp}:$Port"
            DetectedLanIp = $lanIp
            BindHost      = $bind
            AllowsRemote  = $allowsRemote
            Source        = "lanIp"
        }
    }

    return [PSCustomObject]@{
        SuggestedUrl  = "http://localhost:$Port"
        DetectedLanIp = ""
        BindHost      = $bind
        AllowsRemote  = $false
        Source        = "localhost"
    }
}

function Get-LocFleetEnrollToken {
    $settings = Get-LocSettings
    $token = if ($settings.fleetEnrollToken) { [string]$settings.fleetEnrollToken } else { "" }
    $publicUrl = if ($settings.fleetPublicUrl) { [string]$settings.fleetPublicUrl } else { "" }
    $port = if ($settings.port) { [int]$settings.port } else { 8787 }
    $bind = if ($settings.bindHost) { [string]$settings.bindHost } else { "localhost" }
    $hint = Get-LocFleetSuggestedServerUrl -PublicUrl $publicUrl -BindHost $bind -Port $port

    $bindMismatch = $false
    $bindWarning = ""
    $suggestedIsRemote = $hint.SuggestedUrl -and ($hint.SuggestedUrl -notmatch '(?i)localhost|127\.0\.0\.1')
    if ($suggestedIsRemote -and -not $hint.AllowsRemote) {
        $bindMismatch = $true
        $bindWarning = "Suggested agent URL is $($hint.SuggestedUrl) but bindHost is '$bind' (localhost only). Remote agents will fail to connect. Set bindHost to 0.0.0.0 and restart."
    }

    return New-ApiResult -Success $true -Message "Enrollment token" -Data @{
        Token         = $token
        SuggestedUrl  = $hint.SuggestedUrl
        PublicUrl     = $publicUrl
        DetectedLanIp = $hint.DetectedLanIp
        BindHost      = $hint.BindHost
        AllowsRemote  = [bool]$hint.AllowsRemote
        UrlSource     = $hint.Source
        BindMismatch  = $bindMismatch
        BindWarning   = $bindWarning
    }
}

function Get-LocFleetScripts {
    $data = Get-LocFleetScriptsData
    $list = @()
    if ($data.scripts) { $list = @($data.scripts) }
    return New-ApiResult -Success $true -Message "Script library" -Data @($list)
}

function Get-LocFleetScriptContent {
    param([Parameter(Mandatory)] [string]$ScriptId)

    $data = Get-LocFleetScriptsData
    $script = $null
    if ($data.scripts) {
        $script = @($data.scripts) | Where-Object { [string]$_.Id -eq $ScriptId } | Select-Object -First 1
    }
    if (-not $script) {
        return New-ApiResult -Success $false -Message "Script not found" -StatusCode 404
    }

    $root = Get-LocRoot
    $path = Join-Path $root ($script.Path -replace '/', '\')
    if (-not (Test-Path $path)) {
        return New-ApiResult -Success $false -Message "Script file missing" -StatusCode 404
    }

    $content = Get-Content $path -Raw -Encoding UTF8
    return New-ApiResult -Success $true -Message "Script content" -Data @{
        Id      = $script.Id
        Name    = $script.Name
        Content = $content
        Sha256  = $script.Sha256
    }
}

function Register-LocFleetEvent {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [object]$Event = $null
    )

    Add-LocFleetAudit -Action "AgentEvent" -AgentId $AgentId -Detail $Event
    return New-ApiResult -Success $true -Message "Event recorded" -Data @{}
}

function Get-LocFleetAgentPackageDir {
    $dir = Join-Path (Get-LocFleetDir) 'agent-package'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-LocFleetAgentSourcePath {
    $root = Get-LocRoot
    $path = Join-Path $root 'agent\LocalOpsAgent.ps1'
    return $path
}

function Read-LocAgentVersionFromScript {
    param([Parameter(Mandatory)][string]$Content)
    if ($Content -match '\$AgentVersion\s*=\s*"([^"]+)"') {
        return [string]$Matches[1]
    }
    return '0.0.0'
}

function Publish-LocFleetAgentPackage {
    $src = Get-LocFleetAgentSourcePath
    if (-not (Test-Path $src)) {
        return New-ApiResult -Success $false -Message "Agent source missing at agent/LocalOpsAgent.ps1" -StatusCode 404
    }

    try {
        $content = Get-Content -Path $src -Raw -Encoding UTF8
        $version = Read-LocAgentVersionFromScript -Content $content
        $sha = (Get-FileHash -Path $src -Algorithm SHA256).Hash.ToLowerInvariant()
        $pkgDir = Get-LocFleetAgentPackageDir
        $dest = Join-Path $pkgDir 'LocalOpsAgent.ps1'
        Copy-Item -Path $src -Destination $dest -Force

        $installSrc = Join-Path (Split-Path $src -Parent) 'Install-LocalOpsAgent.ps1'
        if (Test-Path $installSrc) {
            Copy-Item -Path $installSrc -Destination (Join-Path $pkgDir 'Install-LocalOpsAgent.ps1') -Force
        }

        $manifest = [ordered]@{
            Version     = $version
            Sha256      = $sha
            FileName    = 'LocalOpsAgent.ps1'
            SizeBytes   = (Get-Item $dest).Length
            PublishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $manifestPath = Join-Path $pkgDir 'manifest.json'
        ($manifest | ConvertTo-Json -Depth 4) | Set-Content -Path $manifestPath -Encoding UTF8

        Add-LocFleetAudit -Action 'AgentPackagePublished' -Detail $manifest
        Write-LocLog -Module 'FLEET' -Action 'PublishAgentPackage' -Level 'INFO' -Message ("Published agent package {0} sha={1}" -f $version, $sha)

        return New-ApiResult -Success $true -Message 'Agent package published' -Data $manifest
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

function Get-LocFleetAgentPackageManifest {
    param([switch]$AutoPublish)

    $pkgDir = Get-LocFleetAgentPackageDir
    $manifestPath = Join-Path $pkgDir 'manifest.json'
    $scriptPath = Join-Path $pkgDir 'LocalOpsAgent.ps1'

    if (-not (Test-Path $manifestPath) -or -not (Test-Path $scriptPath)) {
        if ($AutoPublish) {
            $pub = Publish-LocFleetAgentPackage
            if (-not $pub.Success) { return $pub }
            return New-ApiResult -Success $true -Message 'Agent package' -Data $pub.Data
        }
        return New-ApiResult -Success $false -Message 'Agent package not published' -StatusCode 404
    }

    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return New-ApiResult -Success $true -Message 'Agent package' -Data $manifest
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

function Get-LocFleetAgentPackageContent {
    $manifestRes = Get-LocFleetAgentPackageManifest -AutoPublish
    if (-not $manifestRes.Success) { return $manifestRes }

    $pkgDir = Get-LocFleetAgentPackageDir
    $scriptPath = Join-Path $pkgDir 'LocalOpsAgent.ps1'
    if (-not (Test-Path $scriptPath)) {
        return New-ApiResult -Success $false -Message 'Agent package file missing' -StatusCode 404
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $sha = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest = $manifestRes.Data
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        return New-ApiResult -Success $true -Message 'Agent package content' -Data @{
            Version       = [string]$manifest.Version
            Sha256        = $sha
            ContentBase64 = [Convert]::ToBase64String($bytes)
            Content       = $text
            FileName      = 'LocalOpsAgent.ps1'
        }
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}
