# core/FleetScripts.ps1 - Script library and agent self-update package

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

function Get-LocFleetAgentPackageDir {
    $dir = Join-Path (Get-LocFleetDir) 'agent-package'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-LocFleetAgentSourcePath {
    return (Join-Path (Get-LocRoot) 'agent\LocalOpsAgent.ps1')
}

function Get-LocFleetAgentRuntimeFiles {
    $dir = Split-Path (Get-LocFleetAgentSourcePath) -Parent
    $names = @(
        'LocalOpsAgent.ps1', 'AgentCommon.ps1', 'CapabilityDetector.ps1', 'AgentTelemetry.ps1',
        'CommandDispatcher.ps1', 'AgentCommands.Core.ps1', 'AgentCommands.Local.ps1',
        'AgentCommands.Net.ps1', 'AgentCommands.Software.ps1', 'AgentCommands.Maint.ps1',
        'AgentCommands.Security.ps1', 'Install-LocalOpsAgent.ps1'
    )
    $files = @()
    foreach ($n in $names) {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { $files += (Get-Item -LiteralPath $p) }
    }
    return $files
}

function Read-LocAgentVersionFromScript {
    param([Parameter(Mandatory)][string]$Content)
    if ($Content -match '\$AgentVersion\s*=\s*"([^"]+)"') {
        return [string]$Matches[1]
    }
    return '0.0.0'
}

function Publish-LocFleetAgentPackage {
    $src = Get-LocFleetAgentSourcePath
    if (-not (Test-Path $src)) {
        return New-ApiResult -Success $false -Message "Agent source missing at agent/LocalOpsAgent.ps1" -StatusCode 404
    }

    try {
        $content = Get-Content -Path $src -Raw -Encoding UTF8
        $version = Read-LocAgentVersionFromScript -Content $content
        $sha = (Get-FileHash -Path $src -Algorithm SHA256).Hash.ToLowerInvariant()
        $pkgDir = Get-LocFleetAgentPackageDir

        # Clear prior runtime copies (keep manifest until rewritten)
        Get-ChildItem -Path $pkgDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.ps1' } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $fileEntries = @()
        foreach ($f in @(Get-LocFleetAgentRuntimeFiles)) {
            Copy-Item -Path $f.FullName -Destination (Join-Path $pkgDir $f.Name) -Force
            $fileEntries += [ordered]@{
                FileName  = $f.Name
                Sha256    = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                SizeBytes = $f.Length
            }
        }

        $dest = Join-Path $pkgDir 'LocalOpsAgent.ps1'
        $manifest = [ordered]@{
            Version     = $version
            Sha256      = $sha
            FileName    = 'LocalOpsAgent.ps1'
            SizeBytes   = (Get-Item $dest).Length
            Files       = @($fileEntries)
            PublishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $manifestPath = Join-Path $pkgDir 'manifest.json'
        ($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path $manifestPath -Encoding UTF8

        Add-LocFleetAudit -Action 'AgentPackagePublished' -Detail $manifest
        Write-LocLog -Module 'FLEET' -Action 'PublishAgentPackage' -Level 'INFO' -Message ("Published agent package {0} sha={1} files={2}" -f $version, $sha, $fileEntries.Count)

        return New-ApiResult -Success $true -Message 'Agent package published' -Data $manifest
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

function Get-LocFleetAgentPackageManifest {
    param([switch]$AutoPublish)

    $pkgDir = Get-LocFleetAgentPackageDir
    $manifestPath = Join-Path $pkgDir 'manifest.json'
    $scriptPath = Join-Path $pkgDir 'LocalOpsAgent.ps1'

    if (-not (Test-Path $manifestPath) -or -not (Test-Path $scriptPath)) {
        if ($AutoPublish) {
            $pub = Publish-LocFleetAgentPackage
            if (-not $pub.Success) { return $pub }
            return New-ApiResult -Success $true -Message 'Agent package' -Data $pub.Data
        }
        return New-ApiResult -Success $false -Message 'Agent package not published' -StatusCode 404
    }

    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return New-ApiResult -Success $true -Message 'Agent package' -Data $manifest
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

function Get-LocFleetAgentPackageContent {
    $manifestRes = Get-LocFleetAgentPackageManifest -AutoPublish
    if (-not $manifestRes.Success) { return $manifestRes }

    $pkgDir = Get-LocFleetAgentPackageDir
    $scriptPath = Join-Path $pkgDir 'LocalOpsAgent.ps1'
    if (-not (Test-Path $scriptPath)) {
        return New-ApiResult -Success $false -Message 'Agent package file missing' -StatusCode 404
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $sha = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest = $manifestRes.Data
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)

        $files = @()
        Get-ChildItem -Path $pkgDir -Filter '*.ps1' -File | ForEach-Object {
            $b = [System.IO.File]::ReadAllBytes($_.FullName)
            $files += @{
                FileName      = $_.Name
                Sha256        = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                SizeBytes     = $_.Length
                ContentBase64 = [Convert]::ToBase64String($b)
            }
        }

        return New-ApiResult -Success $true -Message 'Agent package content' -Data @{
            Version       = [string]$manifest.Version
            Sha256        = $sha
            ContentBase64 = [Convert]::ToBase64String($bytes)
            Content       = $text
            FileName      = 'LocalOpsAgent.ps1'
            Files         = @($files)
        }
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}
