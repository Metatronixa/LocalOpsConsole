# core/Fleet.ps1 - Fleet RMM business logic

$script:LocFleetCommandTypes = @(
    'RestartSpooler', 'FlushDns', 'RestartService', 'RunScript', 'Message',
    'CollectInventory', 'RestartComputer', 'GetServices', 'GetProcesses'
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

function ConvertTo-LocFleetAgentSummary {
    param(
        [Parameter(Mandatory)] $Agent,
        [int]$OfflineSeconds
    )

    $lastSeen = if ($Agent.LastSeen) { [datetime]$Agent.LastSeen } else { [datetime]::MinValue }
    $online = ((Get-Date) - $lastSeen).TotalSeconds -le $OfflineSeconds
    $tel = $Agent.Telemetry
    if (-not $tel) { $tel = @{} }

    return [PSCustomObject]@{
        Id            = [string]$Agent.Id
        ComputerName  = [string]$Agent.ComputerName
        Online        = $online
        LastSeen      = if ($Agent.LastSeen) { [string]$Agent.LastSeen } else { $null }
        AgentVersion  = if ($Agent.AgentVersion) { [string]$Agent.AgentVersion } else { "" }
        Revoked       = [bool]$Agent.Revoked
        CpuPct        = if ($tel.CpuPct -ne $null) { [double]$tel.CpuPct } else { $null }
        RamPct        = if ($tel.RamPct -ne $null) { [double]$tel.RamPct } else { $null }
        DiskFreePct   = if ($tel.DiskFreePct -ne $null) { [double]$tel.DiskFreePct } else { $null }
        InternetOk    = if ($tel.InternetOk -ne $null) { [bool]$tel.InternetOk } else { $null }
        UserName      = if ($tel.UserName) { [string]$tel.UserName } else { "" }
        IPv4          = if ($tel.IPv4) { [string]$tel.IPv4 } else { "" }
        Inventory     = $Agent.Inventory
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
    $list = @()

    if ($data.agents -is [PSCustomObject]) {
        foreach ($p in $data.agents.PSObject.Properties) {
            if (-not $p.Value.Revoked) {
                $list += ConvertTo-LocFleetAgentSummary -Agent $p.Value -OfflineSeconds $offline
            }
        }
    }
    elseif ($data.agents -is [hashtable]) {
        foreach ($k in $data.agents.Keys) {
            $a = $data.agents[$k]
            if (-not $a.Revoked) {
                $list += ConvertTo-LocFleetAgentSummary -Agent $a -OfflineSeconds $offline
            }
        }
    }

    return New-ApiResult -Success $true -Message "Agents" -Data @($list | Sort-Object ComputerName)
}

function Get-LocFleetAgentDetail {
    param([Parameter(Mandatory)] [string]$AgentId)

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent) {
        return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
    }

    $offline = Get-LocFleetOfflineSeconds
    $summary = ConvertTo-LocFleetAgentSummary -Agent $agent -OfflineSeconds $offline
    $cmds = Get-LocFleetCommandsForAgent -AgentId $AgentId -Limit 50
    $alerts = Get-LocFleetAlertsForAgent -AgentId $AgentId -Limit 20

    return New-ApiResult -Success $true -Message "Agent detail" -Data @{
        Agent    = $summary
        Commands = $cmds
        Alerts   = $alerts
    }
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

    $cmdId = [guid]::NewGuid().ToString("N")
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $cmd = [ordered]@{
        Id          = $cmdId
        AgentId     = $AgentId
        Type        = $Type
        Payload     = if ($null -eq $Payload) { @{} } else { $Payload }
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

function Claim-LocFleetCommands {
    param([Parameter(Mandatory)] [string]$AgentId)

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent -or $agent.Revoked) {
        return New-ApiResult -Success $false -Message "Unknown or revoked agent" -StatusCode 403
    }

    $claimed = @()
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $data = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($data.commands) { $list = @($data.commands) }

        for ($i = 0; $i -lt $list.Count; $i++) {
            $c = $list[$i]
            if ([string]$c.AgentId -eq $AgentId -and [string]$c.Status -eq "Pending") {
                $c.Status = "Running"
                $c.ClaimedAt = $now
                $list[$i] = $c
                $claimed += [PSCustomObject]@{
                    Id      = $c.Id
                    Type    = $c.Type
                    Payload = $c.Payload
                }
            }
        }

        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    return New-ApiResult -Success $true -Message "Poll" -Data @($claimed)
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

    Add-LocFleetAudit -Action "CommandResult" -AgentId $AgentId -Detail @{
        CommandId  = $CommandId
        Success    = $Success
        Message    = $Message
        ExitCode   = $ExitCode
        DurationMs = $DurationMs
    }

    return New-ApiResult -Success $true -Message "Result recorded" -Data @{ CommandId = $CommandId }
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

    if ($Telemetry.CpuPct -ne $null -and [double]$Telemetry.CpuPct -ge 95) {
        Add-LocFleetAlert -AgentId $AgentId -Type "HighCpu" -Message "CPU at $($Telemetry.CpuPct)%" -Detail @{ CpuPct = $Telemetry.CpuPct }
    }
    if ($Telemetry.DiskFreePct -ne $null -and [double]$Telemetry.DiskFreePct -lt 10) {
        Add-LocFleetAlert -AgentId $AgentId -Type "LowDisk" -Message "Disk free $($Telemetry.DiskFreePct)%" -Detail @{ DiskFreePct = $Telemetry.DiskFreePct }
    }
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

    return New-ApiResult -Success $true -Message "Enrollment token" -Data @{
        Token         = $token
        SuggestedUrl  = $hint.SuggestedUrl
        PublicUrl     = $publicUrl
        DetectedLanIp = $hint.DetectedLanIp
        BindHost      = $hint.BindHost
        AllowsRemote  = [bool]$hint.AllowsRemote
        UrlSource     = $hint.Source
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
