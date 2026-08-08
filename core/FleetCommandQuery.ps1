# core/FleetCommandQuery.ps1 - Command inventory helpers and list API

function Update-LocFleetAgentLastOffender {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] $Offender
    )

    $targetAgentId = $AgentId
    $offenderPayload = $Offender
    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) { $agentsHash[$p.Name] = $p.Value }
        }
        elseif ($data.agents -is [hashtable]) { $agentsHash = @{} + $data.agents }

        if ($agentsHash.ContainsKey($targetAgentId)) {
            $rec = $agentsHash[$targetAgentId]
            $top = $null
            try {
                if ($offenderPayload.TopProcesses) {
                    $list = @($offenderPayload.TopProcesses)
                    if ($list.Count -gt 0) { $top = $list[0] }
                }
            }
            catch { Write-Debug $_.Exception.Message }
            $payload = [ordered]@{
                CapturedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                TopProcess   = $top
                RelatedService = $(if ($offenderPayload.RelatedService) { $offenderPayload.RelatedService } else { $null })
                Summary      = $(if ($offenderPayload.Summary) { [string]$offenderPayload.Summary } else { '' })
            }
            if ($rec -is [PSCustomObject]) {
                $rec | Add-Member -NotePropertyName LastOffender -NotePropertyValue $payload -Force
            }
            else { $rec.LastOffender = $payload }
            $agentsHash[$targetAgentId] = $rec
            Write-LocFleetJson -FileName "agents.json" -Data @{ agents = $agentsHash }
        }
    }
}

function Update-LocFleetAgentInventory {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] $Inventory
    )

    $targetAgentId = $AgentId
    $inventoryPayload = $Inventory
    Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        $agentsHash = @{}
        if ($data.agents -is [PSCustomObject]) {
            foreach ($p in $data.agents.PSObject.Properties) { $agentsHash[$p.Name] = $p.Value }
        }
        elseif ($data.agents -is [hashtable]) { $agentsHash = @{} + $data.agents }

        if ($agentsHash.ContainsKey($targetAgentId)) {
            $rec = $agentsHash[$targetAgentId]
            if ($rec -is [PSCustomObject]) {
                $rec | Add-Member -NotePropertyName Inventory -NotePropertyValue $inventoryPayload -Force
            }
            else { $rec.Inventory = $inventoryPayload }
            $agentsHash[$targetAgentId] = $rec
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

