# core/FleetPackages.ps1 - Policy packs and software package catalog

function Get-LocFleetPolicyPackDir {
    return (Join-Path (Get-LocRoot) "data\fleet\policy-packs")
}

function Get-LocFleetPolicyPackById {
    param([Parameter(Mandatory)] [string]$PackId)
    $dir = Get-LocFleetPolicyPackDir
    $path = Join-Path $dir ("{0}.json" -f $PackId)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-LocFleetPolicyPacks {
    $dir = Get-LocFleetPolicyPackDir
    $list = @()
    if (Test-Path -LiteralPath $dir) {
        Get-ChildItem -Path $dir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($p -and $p.id) {
                    $list += [PSCustomObject]@{
                        Id          = [string]$p.id
                        Name        = [string]$p.name
                        Version     = [string]$p.version
                        Description = [string]$p.description
                        Controls    = @($p.controls)
                    }
                }
            }
            catch { Write-Debug $_.Exception.Message }
        }
    }
    return New-ApiResult -Success $true -Message "Policy packs" -Data @($list)
}

function Test-LocFleetPackageId {
    param([Parameter(Mandatory)][string]$PackageId)
    return [bool]($PackageId -match '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$')
}

function Get-LocFleetSoftwareDir {
    $dir = Join-Path (Get-LocFleetDir) 'software'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Resolve-LocFleetInstallerFileName {
    param([string]$FileName)
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $null }
    $name = [System.IO.Path]::GetFileName($FileName.Trim())
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    if ($name -match '[\\/]' -or $name -eq '.' -or $name -eq '..') { return $null }
    return $name
}

function Get-LocFleetPackageSource {
    param([Parameter(Mandatory)]$Package)
    $src = ''
    try {
        if ($null -ne $Package.Source) { $src = [string]$Package.Source }
    }
    catch { Write-Debug $_.Exception.Message }
    if (-not [string]::IsNullOrWhiteSpace($src)) {
        return $src.Trim().ToLowerInvariant()
    }
    $winget = ''
    $fileName = ''
    $url = ''
    try { if ($null -ne $Package.WingetId) { $winget = [string]$Package.WingetId } } catch { Write-Debug $_.Exception.Message }
    try { if ($null -ne $Package.FileName) { $fileName = [string]$Package.FileName } } catch { Write-Debug $_.Exception.Message }
    try { if ($null -ne $Package.Url) { $url = [string]$Package.Url } } catch { Write-Debug $_.Exception.Message }
    if (-not [string]::IsNullOrWhiteSpace($winget)) { return 'winget' }
    if (-not [string]::IsNullOrWhiteSpace($fileName)) { return 'local' }
    if (-not [string]::IsNullOrWhiteSpace($url)) { return 'url' }
    return 'unknown'
}

function ConvertTo-LocFleetPackageHashtable {
    param([Parameter(Mandatory)]$Package)
    $h = [ordered]@{
        Id       = [string]$Package.Id
        Name     = [string]$Package.Name
        Category = if ($Package.Category) { [string]$Package.Category } else { '' }
        Source   = Get-LocFleetPackageSource -Package $Package
    }
    if ($Package.WingetId) { $h.WingetId = [string]$Package.WingetId }
    if ($Package.Url) { $h.Url = [string]$Package.Url }
    if ($Package.FileName) { $h.FileName = [string]$Package.FileName }
    if ($Package.SilentArgs) { $h.SilentArgs = [string]$Package.SilentArgs }
    if ($Package.Sha256) { $h.Sha256 = [string]$Package.Sha256 }
    return $h
}

function Get-LocFleetDefaultPackages {
    return @(
        @{ Id = 'chrome'; Name = 'Google Chrome'; WingetId = 'Google.Chrome'; Category = 'Browser'; Source = 'winget' }
        @{ Id = 'edge'; Name = 'Microsoft Edge'; WingetId = 'Microsoft.Edge'; Category = 'Browser'; Source = 'winget' }
        @{ Id = 'firefox'; Name = 'Mozilla Firefox'; WingetId = 'Mozilla.Firefox'; Category = 'Browser'; Source = 'winget' }
        @{ Id = 'adobe-reader'; Name = 'Adobe Acrobat Reader'; WingetId = 'Adobe.Acrobat.Reader.64-bit'; Category = 'Productivity'; Source = 'winget' }
        @{ Id = '7zip'; Name = '7-Zip'; WingetId = '7zip.7zip'; Category = 'Utility'; Source = 'winget' }
        @{ Id = 'vcredist'; Name = 'Visual C++ Redistributable 2015-2022'; WingetId = 'Microsoft.VCRedist.2015+.x64'; Category = 'Runtime'; Source = 'winget' }
        @{ Id = 'winrar'; Name = 'WinRAR'; WingetId = 'RARLab.WinRAR'; Category = 'Utility'; Source = 'winget' }
        @{ Id = 'windirstat'; Name = 'WinDirStat'; WingetId = 'WinDirStat.WinDirStat'; Category = 'Utility'; Source = 'winget' }
    )
}

function Save-LocFleetPackages {
    param([Parameter(Mandatory)][object[]]$Packages)
    $normalized = @($Packages | ForEach-Object { ConvertTo-LocFleetPackageHashtable -Package $_ })
    Invoke-LocFleetFileLock -Name 'packages' -Action {
        Write-LocFleetJson -FileName 'packages.json' -Data @{ packages = $normalized }
    }
    return $normalized
}

function Get-LocFleetPackages {
    $null = Get-LocFleetSoftwareDir
    $path = Join-Path (Get-LocFleetDir) 'packages.json'
    if (-not (Test-Path $path)) {
        $seed = @{ packages = @(Get-LocFleetDefaultPackages) }
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ($seed | ConvertTo-Json -Depth 6) | Set-Content -Path $path -Encoding UTF8
    }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $list = @()
        if ($raw.packages) {
            $list = @($raw.packages | ForEach-Object { ConvertTo-LocFleetPackageHashtable -Package $_ })
        }
        return New-ApiResult -Success $true -Message 'Packages' -Data @($list)
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
    }
}

function Get-LocFleetPackageById {
    param([Parameter(Mandatory)][string]$PackageId)
    $res = Get-LocFleetPackages
    if (-not $res.Success) { return $null }
    return @($res.Data) | Where-Object { [string]$_.Id -eq $PackageId } | Select-Object -First 1
}

function Register-LocFleetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Name = '',
        [string]$Category = '',
        [string]$Source = '',
        [string]$WingetId = '',
        [string]$Url = '',
        [string]$FileName = '',
        [string]$SilentArgs = '',
        [string]$Sha256 = ''
    )

    $pkgId = $Id.Trim()
    if (-not (Test-LocFleetPackageId -PackageId $pkgId)) {
        return New-ApiResult -Success $false -Message 'Invalid package Id (letters, digits, . _ - ; 1-64 chars)' -StatusCode 400
    }

    $src = if ($Source) { $Source.Trim().ToLowerInvariant() } else { '' }
    if ([string]::IsNullOrWhiteSpace($src)) {
        if (-not [string]::IsNullOrWhiteSpace($WingetId)) { $src = 'winget' }
        elseif (-not [string]::IsNullOrWhiteSpace($FileName)) { $src = 'local' }
        elseif (-not [string]::IsNullOrWhiteSpace($Url)) { $src = 'url' }
        else {
            return New-ApiResult -Success $false -Message 'Provide WingetId, local FileName, or Url' -StatusCode 400
        }
    }
    if ($src -notin @('winget', 'local', 'url')) {
        return New-ApiResult -Success $false -Message 'Source must be winget, local, or url' -StatusCode 400
    }

    $entry = [ordered]@{
        Id       = $pkgId
        Name     = if ($Name) { $Name.Trim() } else { $pkgId }
        Category = if ($Category) { $Category.Trim() } else { '' }
        Source   = $src
    }

    switch ($src) {
        'winget' {
            if ([string]::IsNullOrWhiteSpace($WingetId)) {
                return New-ApiResult -Success $false -Message 'WingetId required for winget packages' -StatusCode 400
            }
            $entry.WingetId = $WingetId.Trim()
        }
        'url' {
            $u = if ($Url) { $Url.Trim() } else { '' }
            if ($u -notmatch '^https://') {
                return New-ApiResult -Success $false -Message 'Url must be HTTPS' -StatusCode 400
            }
            $entry.Url = $u
            if (-not [string]::IsNullOrWhiteSpace($SilentArgs)) { $entry.SilentArgs = $SilentArgs.Trim() }
            if (-not [string]::IsNullOrWhiteSpace($Sha256)) { $entry.Sha256 = $Sha256.Trim().ToLowerInvariant() }
        }
        'local' {
            $safeName = Resolve-LocFleetInstallerFileName -FileName $FileName
            if (-not $safeName) {
                return New-ApiResult -Success $false -Message 'FileName required (basename only, e.g. Setup.exe)' -StatusCode 400
            }
            $pkgDir = Join-Path (Get-LocFleetSoftwareDir) $pkgId
            $installerPath = Join-Path $pkgDir $safeName
            if (-not (Test-Path -LiteralPath $installerPath)) {
                return New-ApiResult -Success $false -Message "Installer not found. Place file at data/fleet/software/$pkgId/$safeName then register." -StatusCode 400
            }
            $hash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $entry.FileName = $safeName
            $entry.Sha256 = $hash
            if (-not [string]::IsNullOrWhiteSpace($SilentArgs)) { $entry.SilentArgs = $SilentArgs.Trim() }
            else { $entry.SilentArgs = '/S' }
        }
    }

    $res = Get-LocFleetPackages
    if (-not $res.Success) { return $res }
    $list = [System.Collections.ArrayList]@($res.Data)
    $idx = -1
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ([string]$list[$i].Id -eq $pkgId) { $idx = $i; break }
    }
    if ($idx -ge 0) { $list[$idx] = $entry } else { [void]$list.Add($entry) }

    $saved = Save-LocFleetPackages -Packages @($list)
    $out = @($saved) | Where-Object { [string]$_.Id -eq $pkgId } | Select-Object -First 1
    Add-LocFleetAudit -Action 'PackageRegistered' -Detail $entry
    Write-LocLog -Module 'FLEET' -Action 'RegisterPackage' -Level 'INFO' -Message ("Registered package {0} ({1})" -f $pkgId, $src)
    return New-ApiResult -Success $true -Message 'Package registered' -Data $out
}

