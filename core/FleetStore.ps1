# core/FleetStore.ps1 - JSON file storage for fleet RMM

$script:LocFleetDir = $null
$script:LocFleetLock = [System.Collections.Hashtable]::Synchronized(@{})

function Get-LocFleetDir {
    if (-not $script:LocFleetDir) {
        $script:LocFleetDir = Join-Path (Get-LocRoot) "data\fleet"
    }
    return $script:LocFleetDir
}

function Invoke-LocFleetFileLock {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $lockObj = $script:LocFleetLock
    if (-not $lockObj.ContainsKey($Name)) {
        $lockObj[$Name] = New-Object System.Object
    }

    [System.Threading.Monitor]::Enter($lockObj[$Name])
    try {
        return & $Action
    }
    finally {
        [System.Threading.Monitor]::Exit($lockObj[$Name])
    }
}

function Read-LocFleetJson {
    param(
        [Parameter(Mandatory)]
        [string]$FileName,
        [object]$Default = $null
    )

    $path = Join-Path (Get-LocFleetDir) $FileName
    if (-not (Test-Path $path)) {
        return $Default
    }

    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-LocLog -Module "FLEET" -Action "ReadJson" -Level "ERROR" -Message "Failed reading $FileName : $($_.Exception.Message)"
        return $Default
    }
}

function Write-LocFleetJson {
    param(
        [Parameter(Mandatory)]
        [string]$FileName,
        [Parameter(Mandatory)]
        [object]$Data
    )

    $dir = Get-LocFleetDir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $path = Join-Path $dir $FileName
    $tmp = "$path.tmp"
    $json = $Data | ConvertTo-Json -Depth 12 -Compress:$false
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path $path) { Remove-Item $path -Force }
    Move-Item $tmp $path -Force
}

function Add-LocFleetAudit {
    param(
        [string]$Action,
        [string]$AgentId = "",
        [object]$Detail = $null
    )

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        Action    = $Action
        AgentId   = $AgentId
        Detail    = $Detail
    }

    $line = ($entry | ConvertTo-Json -Depth 8 -Compress) + "`n"
    $path = Join-Path (Get-LocFleetDir) "audit.jsonl"
    [System.IO.File]::AppendAllText($path, $line, [System.Text.UTF8Encoding]::new($false))
}

function Get-LocFleetAgentsData {
    return Invoke-LocFleetFileLock -Name "agents" -Action {
        $data = Read-LocFleetJson -FileName "agents.json" -Default @{ agents = @{} }
        if ($data -is [PSCustomObject]) {
            if (-not $data.PSObject.Properties['agents']) {
                $data | Add-Member -NotePropertyName agents -NotePropertyValue @{} -Force
            }
        }
        return $data
    }
}

function Save-LocFleetAgentsData {
    param([Parameter(Mandatory)] $Data)
    $payload = $Data
    Invoke-LocFleetFileLock -Name "agents" -Action {
        Write-LocFleetJson -FileName "agents.json" -Data $payload
    }
}

function Get-LocFleetCommandsData {
    return Invoke-LocFleetFileLock -Name "commands" -Action {
        $data = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        if ($data -is [PSCustomObject] -and -not $data.PSObject.Properties['commands']) {
            $data | Add-Member -NotePropertyName commands -NotePropertyValue @() -Force
        }
        return $data
    }
}

function Save-LocFleetCommandsData {
    param([Parameter(Mandatory)] $Data)
    $payload = $Data
    Invoke-LocFleetFileLock -Name "commands" -Action {
        Write-LocFleetJson -FileName "commands.json" -Data $payload
    }
}

function Get-LocFleetAlertsData {
    return Invoke-LocFleetFileLock -Name "alerts" -Action {
        $data = Read-LocFleetJson -FileName "alerts.json" -Default @{ alerts = @() }
        if ($data -is [PSCustomObject] -and -not $data.PSObject.Properties['alerts']) {
            $data | Add-Member -NotePropertyName alerts -NotePropertyValue @() -Force
        }
        return $data
    }
}

function Save-LocFleetAlertsData {
    param([Parameter(Mandatory)] $Data)
    $payload = $Data
    Invoke-LocFleetFileLock -Name "alerts" -Action {
        Write-LocFleetJson -FileName "alerts.json" -Data $payload
    }
}

function Get-LocFleetScriptsData {
    return Invoke-LocFleetFileLock -Name "scripts" -Action {
        $data = Read-LocFleetJson -FileName "scripts.json" -Default @{ scripts = @() }
        if ($data -is [PSCustomObject] -and -not $data.PSObject.Properties['scripts']) {
            $data | Add-Member -NotePropertyName scripts -NotePropertyValue @() -Force
        }
        return $data
    }
}

function Save-LocFleetScriptsData {
    param([Parameter(Mandatory)] $Data)
    $payload = $Data
    Invoke-LocFleetFileLock -Name "scripts" -Action {
        Write-LocFleetJson -FileName "scripts.json" -Data $payload
    }
}

function Get-LocFleetOfflineSeconds {
    $settings = Get-LocSettings
    if ($settings.fleetOfflineSeconds) { return [int]$settings.fleetOfflineSeconds }
    return 90
}

function Test-LocFleetEnabled {
    $settings = Get-LocSettings
    if ($null -eq $settings.fleetEnabled) { return $true }
    return [bool]$settings.fleetEnabled
}
