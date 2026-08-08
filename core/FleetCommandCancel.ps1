# core/FleetCommandCancel.ps1 - Cancel single or stuck fleet commands

function Cancel-LocFleetCommand {
    param(
        [Parameter(Mandatory)] [string]$CommandId,
        [string]$AgentId = "",
        [string]$Reason = "Cancelled by operator"
    )

    $null = $AgentId
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $state = @{ found = $false; updated = $null }

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
                $state.updated = $c
                $state.found = $true
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
            $state.updated = $c
            $state.found = $true
            break
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    if (-not $state.found) {
        return New-ApiResult -Success $false -Message "Command not found" -StatusCode 404
    }

    Add-LocFleetAudit -Action "CommandCancelled" -AgentId ([string]$state.updated.AgentId) -Detail @{
        CommandId = $CommandId
        Type      = [string]$state.updated.Type
        Reason    = $Reason
    }
    Write-LocLog -Module "FLEET" -Action "CancelCommand" -Level "WARN" -Message "Cancelled $CommandId ($Reason)"
    return New-ApiResult -Success $true -Message "Command cancelled" -Data $state.updated
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
