# core/UpdaterApply.ps1 - Download and apply update packages

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
