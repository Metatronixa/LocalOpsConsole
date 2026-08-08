# api/routers/FleetRouter.ps1 - Fleet RMM API routes

function Invoke-LocFleetRouter {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments
    )

    $request = $Context.Request
    $method = $request.HttpMethod.ToUpperInvariant()

    if (-not (Test-LocFleetEnabled)) {
        Send-JsonResponse -Context $Context -Success $false -Message "Fleet is disabled" -StatusCode 503
        return
    }

    # segments: api, v1, fleet, ...
    $sub = if ($Segments.Count -ge 4) { $segments[3] } else { "" }
    $subLower = $sub.ToLower()
    $agentSub = if ($Segments.Count -ge 5) { $Segments[4] } else { "" }

    # Agent HMAC routes
    $agentRoutes = @('enroll', 'heartbeat', 'poll', 'results', 'events')
    $agentPkgSub = if ($agentSub) { $agentSub.ToLower() } else { '' }
    $needsHmac = ($subLower -in $agentRoutes) `
        -or ($subLower -eq 'scripts' -and $agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'content') `
        -or ($subLower -eq 'agent-package' -and $agentPkgSub -in @('manifest', 'content')) `
        -or ($subLower -eq 'packages' -and $agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'content')

    $body = ""
    $bodyHash = @{}
    if ($method -eq "POST") {
        $body = Read-LocRequestBody -Request $request
        $parsed = Parse-LocJsonBody -Body $body
        if ($null -eq $parsed -and -not [string]::IsNullOrWhiteSpace($body)) {
            Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON body" -StatusCode 400
            return
        }
        if ($parsed) { $bodyHash = $parsed }
    }

    $agentId = $null
    if ($needsHmac -and $subLower -ne 'enroll') {
        $auth = Test-LocAgentSignature -Request $request -Body $body
        if (-not $auth.Success) {
            $status = if ($auth.StatusCode) { [int]$auth.StatusCode } else { 401 }
            Send-JsonResponse -Context $Context -Success $false -Message $auth.Message -StatusCode $status
            return
        }
        $agentId = [string]$auth.Data.AgentId
    }

    if ($subLower -in @('scripts', 'enroll-token', 'policy-packs', 'packages', 'agent-package')) {
        [void](Invoke-LocFleetPackageRoutes -Context $Context -SubLower $subLower -Method $method `
                -AgentSub $agentSub -Segments $Segments -BodyHash $bodyHash -Request $request)
        return
    }

    switch ($subLower) {
        'enroll' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Enroll requires POST" -StatusCode 405
                return
            }
            $token = if ($bodyHash.Token) { [string]$bodyHash.Token } else { "" }
            $computer = if ($bodyHash.ComputerName) { [string]$bodyHash.ComputerName } else { "UNKNOWN" }
            $ver = if ($bodyHash.AgentVersion) { [string]$bodyHash.AgentVersion } else { "2.0.0" }
            $caps = @(if ($bodyHash.Capabilities) { $bodyHash.Capabilities | ForEach-Object { [string]$_ } })
            $result = Enroll-LocAgent -Token $token -ComputerName $computer -AgentVersion $ver -Capabilities $caps
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        'heartbeat' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Heartbeat requires POST" -StatusCode 405
                return
            }
            $result = Register-LocHeartbeat -AgentId $agentId -Telemetry $bodyHash
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'poll' {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Poll requires GET" -StatusCode 405
                return
            }
            $result = Claim-LocFleetCommands -AgentId $agentId
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'results' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Results requires POST" -StatusCode 405
                return
            }
            $cmdId = if ($bodyHash.CommandId) { [string]$bodyHash.CommandId } else { "" }
            if (-not $cmdId) {
                Send-JsonResponse -Context $Context -Success $false -Message "CommandId required" -StatusCode 400
                return
            }
            $result = Complete-LocFleetCommand -AgentId $agentId -CommandId $cmdId `
                -Success ([bool](if ($null -ne $bodyHash.Success) { $bodyHash.Success } else { $true })) `
                -Message ([string](if ($bodyHash.Message) { $bodyHash.Message } else { "" })) `
                -Data $bodyHash.Data `
                -ExitCode ([int](if ($bodyHash.ExitCode) { $bodyHash.ExitCode } else { 0 })) `
                -DurationMs ([int](if ($bodyHash.DurationMs) { $bodyHash.DurationMs } else { 0 })) `
                -LogLines @($bodyHash.LogLines)
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        'events' {
            if ($method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Events requires POST" -StatusCode 405
                return
            }
            $result = Register-LocFleetEvent -AgentId $agentId -Event $bodyHash
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'topology' {
            $topoSub = if ($agentSub) { $agentSub.ToLower() } else { "" }
            if ($method -eq "POST" -and $topoSub -eq "device-type") {
                $nodeId = if ($bodyHash.NodeId) { [string]$bodyHash.NodeId } elseif ($bodyHash.nodeId) { [string]$bodyHash.nodeId } else { "" }
                $dtype = if ($bodyHash.DeviceType) { [string]$bodyHash.DeviceType } elseif ($bodyHash.deviceType) { [string]$bodyHash.deviceType } else { "" }
                $mac = if ($bodyHash.MACAddress) { [string]$bodyHash.MACAddress } elseif ($bodyHash.macAddress) { [string]$bodyHash.macAddress } else { "" }
                $ip = if ($bodyHash.IPv4) { [string]$bodyHash.IPv4 } elseif ($bodyHash.ipv4) { [string]$bodyHash.ipv4 } else { "" }
                if ([string]::IsNullOrWhiteSpace($nodeId) -or [string]::IsNullOrWhiteSpace($dtype)) {
                    Send-JsonResponse -Context $Context -Success $false -Message "NodeId and DeviceType required" -StatusCode 400
                    return
                }
                $result = Set-LocFleetDeviceType -NodeId $nodeId -DeviceType $dtype -MacAddress $mac -IPv4 $ip -Operator "operator"
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Use GET /fleet/topology or POST /fleet/topology/device-type" -StatusCode 405
                return
            }
            $result = Get-LocFleetTopology
            $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        'agents' {
            if ($agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'revoke') {
                if ($method -ne "POST") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Revoke requires POST" -StatusCode 405
                    return
                }
                $result = Revoke-LocAgent -AgentId $agentSub
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($agentSub -and $Segments.Count -ge 6 -and $Segments[5].ToLower() -eq 'latency') {
                if ($method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Latency requires GET" -StatusCode 405
                    return
                }
                $target = $request.QueryString["host"]
                $result = Test-LocFleetAgentLatency -AgentId $agentSub -TargetHost $(if ($target) { [string]$target } else { "" })
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($agentSub) {
                if ($method -ne "GET") {
                    Send-JsonResponse -Context $Context -Success $false -Message "Agent detail requires GET" -StatusCode 405
                    return
                }
                $result = Get-LocFleetAgentDetail -AgentId $agentSub
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Agents list requires GET" -StatusCode 405
                return
            }
            $result = Get-LocFleetAgents
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'commands' {
            # POST /fleet/commands/{id}/cancel  or  /fleet/commands/clear-stuck
            $cmdAction = if ($Segments.Count -ge 5) { $Segments[4].ToLower() } else { "" }
            $cmdVerb = if ($Segments.Count -ge 6) { $Segments[5].ToLower() } else { "" }
            if ($method -eq "POST" -and $cmdAction -eq "clear-stuck") {
                $aid = if ($bodyHash.AgentId) { [string]$bodyHash.AgentId } else { "" }
                if (-not $aid) {
                    Send-JsonResponse -Context $Context -Success $false -Message "AgentId required" -StatusCode 400
                    return
                }
                $reason = if ($bodyHash.Reason) { [string]$bodyHash.Reason } else { "Cleared stuck Running/Pending by operator" }
                $result = Cancel-LocFleetStuckCommands -AgentId $aid -Reason $reason
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -eq "POST" -and $cmdAction -and $cmdVerb -eq "cancel") {
                $aid = if ($bodyHash.AgentId) { [string]$bodyHash.AgentId } else { "" }
                $reason = if ($bodyHash.Reason) { [string]$bodyHash.Reason } else { "Cancelled by operator" }
                $result = Cancel-LocFleetCommand -CommandId $cmdAction -AgentId $aid -Reason $reason
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -eq "POST") {
                $aid = if ($bodyHash.AgentId) { [string]$bodyHash.AgentId } else { "" }
                $type = if ($bodyHash.Type) { [string]$bodyHash.Type } else { "" }
                if (-not $aid -or -not $type) {
                    Send-JsonResponse -Context $Context -Success $false -Message "AgentId and Type required" -StatusCode 400
                    return
                }
                $payload = if ($bodyHash.Payload) { $bodyHash.Payload } else { $null }
                $result = Queue-LocFleetCommand -AgentId $aid -Type $type -Payload $payload
                $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
                Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
                return
            }
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Commands require GET or POST" -StatusCode 405
                return
            }
            $filterId = $request.QueryString["agentId"]
            $result = Get-LocFleetCommands -AgentId $filterId
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        'alerts' {
            if ($method -ne "GET") {
                Send-JsonResponse -Context $Context -Success $false -Message "Alerts require GET" -StatusCode 405
                return
            }
            $result = Get-LocFleetAlerts
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data
            return
        }
        default {
            Send-JsonResponse -Context $Context -Success $false -Message "Unknown fleet endpoint" -StatusCode 404
        }
    }
}
