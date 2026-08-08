# Install-LocalOpsConsole.ps1
# Installs a LocalOpsConsole build from a licensed update manifest (SHA-256 when present), extracts, optionally launches.
# Public free downloads are not offered — obtain access via https://www.opsconsole.co.za/get-access.html
[CmdletBinding()]
param(
    [string]$ManifestUrl = "https://www.opsconsole.co.za/uploads/update.json",
    [string]$InstallPath = "",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Join-Path $env:LOCALAPPDATA "LocalOpsConsole"
}

Write-Host "LocalOpsConsole installer (licensed build)" -ForegroundColor Cyan
Write-Host "Manifest: $ManifestUrl"

$manifestJson = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
$latest = [string]$manifestJson.latest
$build = @($manifestJson.builds) | Where-Object { $_.version -eq $latest } | Select-Object -First 1
if (-not $build) {
    $build = @($manifestJson.builds) | Select-Object -First 1
}
if (-not $build -or -not $build.url) {
    throw "No build URL found in manifest."
}

$base = $ManifestUrl.Substring(0, $ManifestUrl.LastIndexOf('/') + 1)
$zipUrl = [string]$build.url
if ($zipUrl -notmatch '^https?://') {
    # Prefer GitHub Releases asset if url is relative builds/...
    if ($zipUrl -match 'builds/(LocalOpsConsole-.+\.zip)$') {
        $asset = $Matches[1]
        $zipUrl = "https://github.com/Metatronixa/LocalOpsConsole/releases/download/v$latest/$asset"
    }
    else {
        $zipUrl = $base + $zipUrl.TrimStart('/')
    }
}

Write-Host "Downloading $zipUrl ..."
$tmpZip = Join-Path $env:TEMP ("LocalOpsConsole-{0}.zip" -f $latest)
Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing

$expected = [string]$build.sha256
if (-not [string]::IsNullOrWhiteSpace($expected)) {
    $actual = (Get-FileHash -Path $tmpZip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) {
        throw "SHA-256 mismatch. Expected $expected got $actual"
    }
    Write-Host "SHA-256 OK" -ForegroundColor Green
}

if (Test-Path $InstallPath) {
    Write-Host "Removing previous install at $InstallPath"
    Remove-Item -Path $InstallPath -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
Expand-Archive -Path $tmpZip -DestinationPath $InstallPath -Force
Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue

Write-Host "Installed to $InstallPath" -ForegroundColor Green
$bat = Join-Path $InstallPath "start.bat"
if ($Launch -and (Test-Path $bat)) {
    Write-Host "Launching..."
    Start-Process -FilePath $bat -WorkingDirectory $InstallPath
}
else {
    Write-Host "Run: $bat"
}
