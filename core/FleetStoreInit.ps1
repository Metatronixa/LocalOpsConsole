# core/FleetStoreInit.ps1 - Fleet store bootstrap and script library index

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
        catch { Write-Debug $_.Exception.Message }

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
