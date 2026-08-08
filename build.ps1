# build.ps1 - Stamp VERSION, produce dist ZIP, optionally publish to website/uploads
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [switch]$PublishWebsite
)

$ErrorActionPreference = "Stop"
$versionPath = Join-Path $Root "VERSION"
if (-not (Test-Path $versionPath)) { throw "VERSION file missing" }
$Version = (Get-Content $versionPath -Raw).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+') { throw "VERSION must be SemVer (got '$Version')" }

$versionJsonPath = Join-Path $Root "version.json"
if (Test-Path $versionJsonPath) {
    $vj = Get-Content $versionJsonPath -Raw | ConvertFrom-Json
    $vj.version = $Version
    ($vj | ConvertTo-Json -Depth 5) | Set-Content $versionJsonPath -Encoding UTF8
}

$indexPath = Join-Path $Root "dashboard\index.html"
if (Test-Path $indexPath) {
    $html = Get-Content $indexPath -Raw
    $html = [regex]::Replace($html, '(id="app-version"[^>]*>)v[\d.]+', "`${1}v$Version")
    Set-Content -Path $indexPath -Value $html -Encoding UTF8
}

$distDir = Join-Path $Root "dist"
if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

$stageName = "LocalOpsConsole-$Version"
$stage = Join-Path $env:TEMP $stageName
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

$include = @("api", "core", "modules", "dashboard", "scripts", "rules", "notifications", "config", "VERSION", "version.json", "settings.json", "start.ps1", "start.bat", "start-silent.vbs", "README.md", "build.ps1", "docs", "ROADMAP.md", "CHANGELOG.md")
foreach ($item in $include) {
    $src = Join-Path $Root $item
    if (-not (Test-Path $src)) { continue }
    $dest = Join-Path $stage $item
    if (Test-Path $src -PathType Container) {
        Copy-Item -Path $src -Destination $dest -Recurse -Force
    }
    else {
        Copy-Item -Path $src -Destination $dest -Force
    }
}

$logs = Join-Path $stage "logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
Set-Content (Join-Path $logs ".gitkeep") -Value "" -Encoding UTF8

foreach ($d in @("data\events", "data\incidents\active", "data\incidents\resolved", "data\incidents\archive", "data\fleet", "data\integrity")) {
    $p = Join-Path $stage $d
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    Set-Content (Join-Path $p ".gitkeep") -Value "" -Encoding UTF8
}

# Generate module integrity hashes into staged package (enforce mode for releases)
Write-Host "Generating integrity hashes..." -ForegroundColor Cyan
. (Join-Path $Root "core\Settings.ps1")
. (Join-Path $Root "core\IntegrityManager.ps1")
Initialize-LocSettings -RootPath $stage
$hashPath = New-LocIntegrityStore -ModulesPath (Join-Path $stage "modules") -Version $Version
# Packaged builds: enforce integrity AND strip machine-local / secret fields.
# Never ship the developer's working settings.json (LAN IPs, enroll tokens, paths).
$stagedSettings = Join-Path $stage "settings.json"
if (Test-Path $stagedSettings) {
    try {
        $sj = Get-Content $stagedSettings -Raw | ConvertFrom-Json
        $sj | Add-Member -NotePropertyName integrityMode -NotePropertyValue "enforce" -Force
        $sj | Add-Member -NotePropertyName bindHost -NotePropertyValue "localhost" -Force
        $sj | Add-Member -NotePropertyName fleetPublicUrl -NotePropertyValue "" -Force
        $sj | Add-Member -NotePropertyName fleetEnrollToken -NotePropertyValue "" -Force
        $sj | Add-Member -NotePropertyName syncMePath -NotePropertyValue "" -Force
        if (-not $sj.PSObject.Properties['updateUrl'] -or [string]::IsNullOrWhiteSpace([string]$sj.updateUrl)) {
            $sj | Add-Member -NotePropertyName updateUrl -NotePropertyValue "https://www.opsconsole.co.za/uploads/update.json" -Force
        }
        $sj | Add-Member -NotePropertyName rustDeskInstallerUrl -NotePropertyValue "" -Force
        $sj | Add-Member -NotePropertyName rustDeskInstallerSha256 -NotePropertyValue "" -Force
        ($sj | ConvertTo-Json -Depth 12) | Set-Content $stagedSettings -Encoding UTF8
        Write-Host "Sanitized staged settings.json (localhost bind, empty secrets)" -ForegroundColor Green
    }
    catch { }
}
Write-Host "Integrity store: $hashPath" -ForegroundColor Green

$zipPath = Join-Path $distDir "$stageName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
Remove-Item $stage -Recurse -Force

Write-Host "Built $zipPath" -ForegroundColor Green
Write-Host "Version $Version" -ForegroundColor Cyan

# Package fleet agent
$agentDir = Join-Path $Root "agent"
if (Test-Path $agentDir) {
    $agentZip = Join-Path $distDir "LocalOpsAgent-$Version.zip"
    if (Test-Path $agentZip) { Remove-Item $agentZip -Force }
    Compress-Archive -Path (Join-Path $agentDir "*") -DestinationPath $agentZip -Force
    Write-Host "Built $agentZip" -ForegroundColor Green
}

if ($PublishWebsite) {
    $uploads = Join-Path $Root "website\uploads"
    $builds = Join-Path $uploads "builds"
    New-Item -ItemType Directory -Force -Path $builds | Out-Null
    $destZip = Join-Path $builds "$stageName.zip"
    Copy-Item -Path $zipPath -Destination $destZip -Force
    $sha = (Get-FileHash -Path $destZip -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item $destZip).Length
    $releasedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    # Feed is served from www.opsconsole.co.za/uploads; ZIP stays on GitHub Releases.
    # Relative builds/... still works if you also mirror the ZIP under uploads/builds/.
    $downloadUrl = "https://github.com/Metatronixa/LocalOpsConsole/releases/download/v$Version/$stageName.zip"
    $manifest = [ordered]@{
        name        = "LocalOpsConsole"
        latest      = $Version
        releasedAt  = $releasedAt
        notes       = "LocalOpsConsole $Version"
        minVersion  = "1.0.0"
        builds      = @(
            [ordered]@{
                version = $Version
                channel = "stable"
                url     = $downloadUrl
                sha256  = $sha
                size    = $size
            }
        )
    }
    $manifestPath = Join-Path $uploads "update.json"
    ($manifest | ConvertTo-Json -Depth 6) | Set-Content -Path $manifestPath -Encoding UTF8
    Write-Host "Published $destZip" -ForegroundColor Green
    Write-Host "Wrote $manifestPath (sha256=$sha)" -ForegroundColor Cyan
}

return $zipPath
