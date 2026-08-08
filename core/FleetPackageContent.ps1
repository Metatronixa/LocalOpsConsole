# core/FleetPackageContent.ps1 - Package remove and local installer download

function Remove-LocFleetPackage {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [switch]$DeleteFiles
    )

    $pkgId = $PackageId.Trim()
    if (-not (Test-LocFleetPackageId -PackageId $pkgId)) {
        return New-ApiResult -Success $false -Message 'Invalid package Id' -StatusCode 400
    }

    $res = Get-LocFleetPackages
    if (-not $res.Success) { return $res }
    $before = @($res.Data)
    $after = @($before | Where-Object { [string]$_.Id -ne $pkgId })
    if ($after.Count -eq $before.Count) {
        return New-ApiResult -Success $false -Message "Package not found: $pkgId" -StatusCode 404
    }

    Save-LocFleetPackages -Packages $after | Out-Null

    if ($DeleteFiles) {
        $pkgDir = Join-Path (Get-LocFleetSoftwareDir) $pkgId
        if (Test-Path -LiteralPath $pkgDir) {
            try { Remove-Item -LiteralPath $pkgDir -Recurse -Force -ErrorAction Stop } catch { Write-Debug $_.Exception.Message }
        }
    }

    Add-LocFleetAudit -Action 'PackageRemoved' -Detail @{ PackageId = $pkgId; DeleteFiles = [bool]$DeleteFiles }
    return New-ApiResult -Success $true -Message 'Package removed' -Data @{ PackageId = $pkgId; DeleteFiles = [bool]$DeleteFiles }
}

function Get-LocFleetPackageContent {
    param([Parameter(Mandatory)][string]$PackageId)

    $pkgId = $PackageId.Trim()
    if (-not (Test-LocFleetPackageId -PackageId $pkgId)) {
        return New-ApiResult -Success $false -Message 'Invalid package Id' -StatusCode 400
    }

    $pkg = Get-LocFleetPackageById -PackageId $pkgId
    if (-not $pkg) {
        return New-ApiResult -Success $false -Message "Package not found: $pkgId" -StatusCode 404
    }

    $src = Get-LocFleetPackageSource -Package $pkg
    if ($src -ne 'local') {
        return New-ApiResult -Success $false -Message 'Content download is only for local packages' -StatusCode 400
    }

    $safeName = Resolve-LocFleetInstallerFileName -FileName ([string]$pkg.FileName)
    if (-not $safeName) {
        return New-ApiResult -Success $false -Message 'Package FileName missing or invalid' -StatusCode 400
    }

    $softwareRoot = [System.IO.Path]::GetFullPath((Get-LocFleetSoftwareDir))
    $installerPath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $softwareRoot $pkgId) $safeName))
    if (-not $installerPath.StartsWith($softwareRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return New-ApiResult -Success $false -Message 'Invalid installer path' -StatusCode 400
    }
    if (-not (Test-Path -LiteralPath $installerPath)) {
        return New-ApiResult -Success $false -Message "Installer file missing: $safeName" -StatusCode 404
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($installerPath)
        $sha = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expected = if ($pkg.Sha256) { ([string]$pkg.Sha256).ToLowerInvariant() } else { '' }
        if ($expected -and $expected -ne $sha) {
            return New-ApiResult -Success $false -Message 'Catalog Sha256 does not match installer on disk; re-register the package' -StatusCode 409
        }
        return New-ApiResult -Success $true -Message 'Package content' -Data @{
            PackageId     = $pkgId
            Name          = [string]$pkg.Name
            FileName      = $safeName
            Sha256        = $sha
            SizeBytes     = $bytes.Length
            SilentArgs    = if ($pkg.SilentArgs) { [string]$pkg.SilentArgs } else { '/S' }
            ContentBase64 = [Convert]::ToBase64String($bytes)
        }
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

