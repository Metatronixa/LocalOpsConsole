# core/Updater.ps1 - Check and apply updates from website/uploads/update.json

function Compare-SemVer {
    param([string]$A, [string]$B)
    $pa = @($A.Split('.') | ForEach-Object { [int]$_ })
    $pb = @($B.Split('.') | ForEach-Object { [int]$_ })
    while ($pa.Count -lt 3) { $pa += 0 }
    while ($pb.Count -lt 3) { $pb += 0 }
    for ($i = 0; $i -lt 3; $i++) {
        if ($pa[$i] -lt $pb[$i]) { return -1 }
        if ($pa[$i] -gt $pb[$i]) { return 1 }
    }
    return 0
}

function Get-UpdateManifestUrl {
    $settings = Get-LocSettings
    if ($settings.PSObject.Properties['updateUrl'] -and $settings.updateUrl) {
        return [string]$settings.updateUrl
    }
    # Default: sibling website/uploads when running from repo layout
    $root = Get-LocRoot
    $local = Join-Path $root "website\uploads\update.json"
    if (Test-Path $local) {
        return ("file:///" + ($local -replace '\\', '/'))
    }
    return $null
}

function Resolve-UpdateAssetUrl {
    param(
        [string]$ManifestUrl,
        [string]$AssetUrl
    )
    if ([string]::IsNullOrWhiteSpace($AssetUrl)) { return $null }
    if ($AssetUrl -match '^(https?|file):') { return $AssetUrl }

    if ($ManifestUrl -like 'file://*') {
        $manifestPath = [Uri]::new($ManifestUrl).LocalPath
        $baseDir = Split-Path $manifestPath -Parent
        $combined = [System.IO.Path]::GetFullPath((Join-Path $baseDir ($AssetUrl -replace '/', '\')))
        return ("file:///" + ($combined -replace '\\', '/'))
    }

    $base = $ManifestUrl
    if ($base.EndsWith('update.json')) {
        $base = $base.Substring(0, $base.Length - 'update.json'.Length)
    }
    elseif (-not $base.EndsWith('/')) {
        $base = $base.Substring(0, $base.LastIndexOf('/') + 1)
    }
    return ([Uri]::new([Uri]::new($base), $AssetUrl)).AbsoluteUri
}

function Get-RemoteText {
    param(
        [string]$Url,
        [int]$TimeoutMs = 8000
    )
    if ($Url -like 'file://*') {
        $path = [Uri]::new($Url).LocalPath
        if (-not (Test-Path $path)) { throw "Manifest not found: $path" }
        return Get-Content -Path $path -Raw -Encoding UTF8
    }
    # HttpWebRequest with timeouts — WebClient has no timeout and can block the single-threaded API.
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"
    $req.UserAgent = "LocalOpsConsole-Updater"
    $req.Timeout = $TimeoutMs
    $req.ReadWriteTimeout = $TimeoutMs
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $resp = $null
    $stream = $null
    $reader = $null
    try {
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($resp) { $resp.Dispose() }
    }
}

function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$TimeoutMs = 120000
    )
    if ($Url -like 'file://*') {
        $path = [Uri]::new($Url).LocalPath
        Copy-Item -Path $path -Destination $OutFile -Force
        return
    }
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"
    $req.UserAgent = "LocalOpsConsole-Updater"
    $req.Timeout = $TimeoutMs
    $req.ReadWriteTimeout = $TimeoutMs
    $resp = $null
    $inStream = $null
    $outStream = $null
    try {
        $resp = $req.GetResponse()
        $inStream = $resp.GetResponseStream()
        $outStream = [System.IO.File]::Create($OutFile)
        $buffer = New-Object byte[] 81920
        while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
        }
    }
    finally {
        if ($outStream) { $outStream.Dispose() }
        if ($inStream) { $inStream.Dispose() }
        if ($resp) { $resp.Dispose() }
    }
}

function Get-FileSha256 {
    param([string]$Path)
    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    return $hash.Hash.ToLowerInvariant()
}

function Test-LocUpdate {
    $current = (Get-LocVersion).version
    $url = Get-UpdateManifestUrl
    if (-not $url) {
        return New-ApiResult -Success $false -Message "updateUrl not configured and no local website/uploads/update.json found" -Data ([PSCustomObject]@{
            CurrentVersion = $current
            UpdateUrl      = $null
        })
    }

    try {
        Write-LocLog -Module "UPDATE" -Action "Check" -Level "INFO" -Message "Fetching $url"
        $json = Get-RemoteText -Url $url
        $manifest = $json | ConvertFrom-Json
        $latest = [string]$manifest.latest
        $cmp = Compare-SemVer -A $current -B $latest
        $updateAvailable = $cmp -lt 0

        $build = @($manifest.builds) | Where-Object { $_.version -eq $latest } | Select-Object -First 1
        if (-not $build -and $manifest.builds) {
            $build = @($manifest.builds) | Select-Object -First 1
        }

        $resolved = $null
        if ($build -and $build.url) {
            $resolved = Resolve-UpdateAssetUrl -ManifestUrl $url -AssetUrl ([string]$build.url)
        }

        return New-ApiResult -Success $true -Message $(if ($updateAvailable) { "Update available: $latest" } else { "Up to date" }) -Data ([PSCustomObject]@{
            CurrentVersion  = $current
            LatestVersion   = $latest
            UpdateAvailable = $updateAvailable
            Notes           = $manifest.notes
            ReleasedAt      = $manifest.releasedAt
            Channel         = if ($build) { $build.channel } else { "stable" }
            DownloadUrl     = $resolved
            Sha256          = if ($build) { $build.sha256 } else { $null }
            Size            = if ($build) { $build.size } else { $null }
            ManifestUrl     = $url
            MinVersion      = $manifest.minVersion
        })
    }
    catch {
        Write-LocLog -Module "UPDATE" -Action "Check" -Level "ERROR" -Message $_.Exception.Message
        return New-ApiResult -Success $false -Message "Update check failed: $($_.Exception.Message)" -Data ([PSCustomObject]@{
            CurrentVersion = $current
            ManifestUrl    = $url
        })
    }
}

function Apply-LocUpdate {
    param([switch]$Force)

    $check = Test-LocUpdate
    if (-not $check.Success) { return $check }
    if (-not $check.Data.UpdateAvailable -and -not $Force) {
        return New-ApiResult -Success $true -Message "Already on latest version" -Data $check.Data
    }
    if (-not $check.Data.DownloadUrl) {
        return New-ApiResult -Success $false -Message "No download URL in manifest" -Data $check.Data
    }

    $root = Get-LocRoot
    $tempRoot = Join-Path $env:TEMP ("LocalOpsConsole-update-" + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tempRoot "update.zip"
    $extractPath = Join-Path $tempRoot "extract"

    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Write-LocLog -Module "UPDATE" -Action "Apply" -Level "INFO" -Message "Downloading $($check.Data.DownloadUrl)"
        Get-RemoteFile -Url $check.Data.DownloadUrl -OutFile $zipPath

        if ($check.Data.Sha256 -and $check.Data.Sha256 -notmatch '^(REPLACE|TODO|\.\.\.)') {
            $actual = Get-FileSha256 -Path $zipPath
            $expected = ([string]$check.Data.Sha256).ToLowerInvariant()
            if ($actual -ne $expected) {
                throw "SHA-256 mismatch. Expected $expected, got $actual"
            }
        }

        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        # ZIP may contain files at root or a single top folder
        $sourceRoot = $extractPath
        $children = Get-ChildItem $extractPath
        if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
            $sourceRoot = $children[0].FullName
        }

        $preserve = @('logs', 'settings.json')
        Get-ChildItem -Path $sourceRoot -Force | ForEach-Object {
            $name = $_.Name
            if ($preserve -contains $name.ToLower() -or $name -eq 'settings.json') {
                return
            }
            $dest = Join-Path $root $name
            if ($_.PSIsContainer) {
                if (Test-Path $dest) {
                    # Merge copy
                    Copy-Item -Path (Join-Path $_.FullName '*') -Destination $dest -Recurse -Force
                }
                else {
                    Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
                }
            }
            else {
                if ($name -eq 'settings.json' -and (Test-Path (Join-Path $root 'settings.json'))) {
                    return
                }
                Copy-Item -Path $_.FullName -Destination $dest -Force
            }
        }

        # Always refresh VERSION / version.json from package
        foreach ($must in @('VERSION', 'version.json')) {
            $src = Join-Path $sourceRoot $must
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination (Join-Path $root $must) -Force
            }
        }

        Initialize-LocSettings -RootPath $root
        Write-LocLog -Module "UPDATE" -Action "Apply" -Level "SUCCESS" -Message "Applied $($check.Data.LatestVersion). Restart recommended."

        return New-ApiResult -Success $true -Message "Update applied to $($check.Data.LatestVersion). Restart the server to load new code." -Data ([PSCustomObject]@{
            AppliedVersion = $check.Data.LatestVersion
            RestartRequired = $true
        })
    }
    catch {
        Write-LocLog -Module "UPDATE" -Action "Apply" -Level "ERROR" -Message $_.Exception.Message
        return New-ApiResult -Success $false -Message "Update apply failed: $($_.Exception.Message)" -StatusCode 500
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
