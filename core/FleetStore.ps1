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
    Invoke-LocFleetFileLock -Name "agents" -Action {
        Write-LocFleetJson -FileName "agents.json" -Data $Data
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
    Invoke-LocFleetFileLock -Name "commands" -Action {
        Write-LocFleetJson -FileName "commands.json" -Data $Data
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
    Invoke-LocFleetFileLock -Name "alerts" -Action {
        Write-LocFleetJson -FileName "alerts.json" -Data $Data
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
    Invoke-LocFleetFileLock -Name "scripts" -Action {
        Write-LocFleetJson -FileName "scripts.json" -Data $Data
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

function Initialize-LocFleetStore {
    $root = Get-LocRoot
    $dataDir = Join-Path $root "data"
    $fleetDir = Join-Path $dataDir "fleet"
    foreach ($d in @($dataDir, $fleetDir)) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    $gitkeepData = Join-Path $dataDir ".gitkeep"
    $gitkeepFleet = Join-Path $fleetDir ".gitkeep"
    if (-not (Test-Path $gitkeepData)) { Set-Content $gitkeepData -Value "" -Encoding UTF8 }
    if (-not (Test-Path $gitkeepFleet)) { Set-Content $gitkeepFleet -Value "" -Encoding UTF8 }

    $script:LocFleetDir = $fleetDir

    # Ensure base files exist
    if (-not (Test-Path (Join-Path $fleetDir "agents.json"))) {
        Write-LocFleetJson -FileName "agents.json" -Data @{ agents = @{} }
    }
    if (-not (Test-Path (Join-Path $fleetDir "commands.json"))) {
        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = @() }
    }
    if (-not (Test-Path (Join-Path $fleetDir "alerts.json"))) {
        Write-LocFleetJson -FileName "alerts.json" -Data @{ alerts = @() }
    }
    if (-not (Test-Path (Join-Path $fleetDir "audit.jsonl"))) {
        Set-Content (Join-Path $fleetDir "audit.jsonl") -Value "" -Encoding UTF8
    }

    # Enrollment token
    $settings = Get-LocSettings
    $token = if ($settings.fleetEnrollToken) { [string]$settings.fleetEnrollToken } else { "" }
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = New-LocEnrollmentToken
        $settingsPath = Join-Path $root "settings.json"
        $settingsObj = @{}
        if (Test-Path $settingsPath) {
            $settingsObj = Get-Content $settingsPath -Raw | ConvertFrom-Json
        }
        $settingsObj | Add-Member -NotePropertyName fleetEnabled -NotePropertyValue $true -Force
        $settingsObj | Add-Member -NotePropertyName fleetEnrollToken -NotePropertyValue $token -Force
        if (-not $settingsObj.PSObject.Properties['fleetOfflineSeconds']) {
            $settingsObj | Add-Member -NotePropertyName fleetOfflineSeconds -NotePropertyValue 90 -Force
        }
        if (-not $settingsObj.PSObject.Properties['fleetPublicUrl']) {
            $settingsObj | Add-Member -NotePropertyName fleetPublicUrl -NotePropertyValue "" -Force
        }
        ($settingsObj | ConvertTo-Json -Depth 5) | Set-Content $settingsPath -Encoding UTF8
        Initialize-LocSettings -RootPath $root
        $settings = Get-LocSettings
    }

    Write-LocFleetJson -FileName "meta.json" -Data @{
        enrollToken = $token
        updatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    Initialize-LocFleetScriptLibrary

    Write-LocLog -Module "FLEET" -Action "Init" -Level "SUCCESS" -Message "Fleet store initialized at $fleetDir"
}

function Initialize-LocFleetScriptLibrary {
    $root = Get-LocRoot
    $scriptsDir = Join-Path $root "scripts\fleet"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    $entries = @()
    $files = Get-ChildItem -Path $scriptsDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $relPath = "scripts/fleet/$($file.Name)"
        $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $desc = ""
        try {
            $firstLines = Get-Content $file.FullName -TotalCount 5 -ErrorAction SilentlyContinue
            $comment = $firstLines | Where-Object { $_ -match '^\s*#' } | Select-Object -First 1
            if ($comment) { $desc = ($comment -replace '^\s*#\s*', '').Trim() }
        }
        catch { }

        $entries += [ordered]@{
            Id          = $id
            Name        = $id -replace '-', ' '
            Description = $desc
            Path        = $relPath
            Sha256      = $hash
        }
    }

    Save-LocFleetScriptsData -Data @{ scripts = $entries }
}
