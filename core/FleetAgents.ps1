# core/FleetAgents.ps1 - Enroll, heartbeat, agent list, revoke, events

function Enroll-LocAgent {
    param(
        [Parameter(Mandatory)] [string]$Token,
        [Parameter(Mandatory)] [string]$ComputerName,
        [string]$AgentVersion = "2.0.0",
        [object[]]$Capabilities = @()
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
    $caps = @($Capabilities | ForEach-Object { [string]$_ } | Where-Object { $_ })

    $record = [ordered]@{
        Id           = $agentId
        ComputerName = $ComputerName
        AgentVersion = $AgentVersion
        Secret       = $secret
        EnrolledAt   = $now
        LastSeen     = $now
        Revoked      = $false
        Capabilities = $caps
        Telemetry    = @{ Capabilities = $caps }
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
            if ($Telemetry.Capabilities) {
                $caps = @($Telemetry.Capabilities | ForEach-Object { [string]$_ })
                $rec | Add-Member -NotePropertyName Capabilities -NotePropertyValue $caps -Force
            }
            $rec | Add-Member -NotePropertyName Telemetry -NotePropertyValue $Telemetry -Force
        }
        else {
            $rec.LastSeen = $now
            if ($Telemetry.ComputerName) { $rec.ComputerName = $Telemetry.ComputerName }
            if ($Telemetry.AgentVersion) { $rec.AgentVersion = $Telemetry.AgentVersion }
            if ($Telemetry.Capabilities) {
                $rec.Capabilities = @($Telemetry.Capabilities | ForEach-Object { [string]$_ })
            }
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

    # Cancel orphan Pending/Running so they cannot rot forever after remove.
    try {
        Cancel-LocFleetStuckCommands -AgentId $AgentId -Reason "Agent removed"
    }
    catch { Write-Debug $_.Exception.Message }

    Add-LocFleetAudit -Action "AgentRevoked" -AgentId $AgentId
    return New-ApiResult -Success $true -Message "Agent removed" -Data @{ AgentId = $AgentId }
}

function Register-LocFleetEvent {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Alias('Event')]
        [object]$LocEvent = $null
    )

    Add-LocFleetAudit -Action "AgentEvent" -AgentId $AgentId -Detail $LocEvent
    return New-ApiResult -Success $true -Message "Event recorded" -Data @{}
}

