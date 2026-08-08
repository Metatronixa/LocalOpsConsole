# core/FleetAlerts.ps1 - Fleet heartbeat alerts and spike enrichment

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
            # Prefer hub playbook auto for high-cpu when enabled (CaptureProcessSnapshot); else legacy offenders.
            $hubQueued = $false
            if ($null -ne $cpu -and $cpu -ge 90 -and (Get-Command Invoke-LocPlaybookFleetAutoForAgent -ErrorAction SilentlyContinue)) {
                $auto = Invoke-LocPlaybookFleetAutoForAgent -RuleId "high-cpu" -AgentId $AgentId -Reason "HighCpu"
                if ($auto -and $auto.Success) { $hubQueued = $true }
            }
            if (-not $hubQueued) {
                $recent = @(Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 15)
                $busy = $false
                foreach ($c in $recent) {
                    if ([string]$c.Type -notin @('GetResourceOffenders', 'CaptureProcessSnapshot')) { continue }
                    if ($c.Status -in @('Pending', 'Running')) { $busy = $true; break }
                    if ($c.Status -eq 'Completed' -and $c.CompletedAt) {
                        try {
                            if (((Get-Date) - [datetime]$c.CompletedAt).TotalSeconds -lt 300) { $busy = $true; break }
                        }
                        catch { Write-Debug $_.Exception.Message }
                    }
                }
                if (-not $busy) {
                    Queue-LocFleetCommand -AgentId $AgentId -Type 'GetResourceOffenders' -Payload @{ Top = 8 } | Out-Null
                }
            }
        }
        catch { Write-Debug $_.Exception.Message }
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
        catch { Write-Debug $_.Exception.Message }
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
    catch { Write-Debug $_.Exception.Message }

    $msg = "{0}: top offender {1}" -f $pcName, $(if ($topName) { $topName } else { 'unknown' })
    if ($null -ne $topPid) { $msg += " (PID $topPid)" }
    if ($svcName) { $msg += " Â· service $svcName" }

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

