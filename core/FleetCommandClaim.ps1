# core/FleetCommandClaim.ps1 - Claim and complete fleet commands

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
            $mins = Get-LocFleetRunningTimeoutMinutes -Type ([string]$c.Type)
            $c.Status = "Failed"
            $c.CompletedAt = $now
            $c.Result = [ordered]@{
                Success    = $false
                Message    = ("Timed out - agent never reported result (Running > {0}m)" -f $mins)
                Data       = $null
                ExitCode   = -1
                DurationMs = 0
                LogLines   = @()
            }
            $list[$i] = $c
            Write-LocLog -Module "FLEET" -Action "Claim" -Level "WARN" -Message "Expired stale Running $($c.Id) ($($c.Type))"
        }

        # Expire Pending that was never claimed (agent Online but poll broken / outdated).
        for ($i = 0; $i -lt $list.Count; $i++) {
            $c = $list[$i]
            if ([string]$c.AgentId -ne $AgentId) { continue }
            if (-not (Test-LocFleetCommandStalePending -Command $c -Now $utcNow)) { continue }
            $c.Status = "Failed"
            $c.CompletedAt = $now
            $c.Result = [ordered]@{
                Success    = $false
                Message    = ("Timed out - never claimed (Pending > {0}m). Restart LocalOpsAgent or reinstall agent; check ServerUrl / poll logs." -f $script:LocFleetPendingNeverClaimedMinutes)
                Data       = $null
                ExitCode   = -1
                DurationMs = 0
                LogLines   = @()
            }
            $list[$i] = $c
            Write-LocLog -Module "FLEET" -Action "Claim" -Level "WARN" -Message "Expired never-claimed Pending $($c.Id) ($($c.Type))"
        }

        # Do not pile up Running jobs while a long command (e.g. SFC) is in flight.
        $hasRunning = $false
        $runningType = ""
        foreach ($c in $list) {
            if ([string]$c.AgentId -eq $AgentId -and [string]$c.Status -eq "Running") {
                $hasRunning = $true
                $runningType = [string]$c.Type
                break
            }
        }
        if ($hasRunning) {
            Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
            Write-LocLog -Module "FLEET" -Action "Claim" -Level "INFO" -Message ("Poll blocked by Running {0} for {1}" -f $runningType, $AgentId)
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
                Write-LocLog -Module "FLEET" -Action "Claim" -Level "INFO" -Message ("Claimed {0} ({1}) for {2}" -f $c.Type, $c.Id, $AgentId)
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
    $logLines = @($LogLines)
    $state = @{ found = $false }

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
                    LogLines   = $logLines
                }
                $list[$i] = $c
                $state.found = $true

                if ($c.Type -eq "CollectInventory" -and $Success -and $Data) {
                    Update-LocFleetAgentInventory -AgentId $AgentId -Inventory $Data
                }
                break
            }
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    if (-not $state.found) {
        return New-ApiResult -Success $false -Message "Command not found" -StatusCode 404
    }

    if ($Success -and $Data) {
        $cmdType = $null
        try {
            $all = Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 50
            $match = @($all | Where-Object { [string]$_.Id -eq $CommandId } | Select-Object -First 1)
            if ($match) { $cmdType = [string]$match[0].Type }
        }
        catch { Write-Debug $_.Exception.Message }
        if ($cmdType -eq 'GetResourceOffenders') {
            try { Update-LocFleetAgentLastOffender -AgentId $AgentId -Offender $Data } catch { Write-Debug $_.Exception.Message }
            try { Enrich-LocFleetSpikeFromOffenders -AgentId $AgentId -Data $Data } catch { Write-Debug $_.Exception.Message }
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

