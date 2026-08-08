# core/FleetAgentOps.ps1 - Agent detail and latency probe

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

