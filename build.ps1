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

$include = @("api", "core", "modules", "dashboard", "scripts", "VERSION", "version.json", "settings.json", "start.ps1", "start.bat", "README.md", "build.ps1", "docs")
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
                url     = "builds/$stageName.zip"
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
