# core/IntegrityManager.ps1 - SHA-256 verification of module scripts

$script:LocIntegrityStore = $null
$script:LocIntegrityMode = "warn"  # warn | enforce

function Get-LocIntegrityPath {
    return Join-Path (Get-LocRoot) "data\integrity\module-hashes.json"
}

function Initialize-LocIntegrityManager {
    param([string]$Mode = "")

    $settings = Get-LocSettings
    if ($Mode) {
        $script:LocIntegrityMode = $Mode
    }
    elseif ($settings -and $settings.PSObject.Properties['integrityMode'] -and $settings.integrityMode) {
        $script:LocIntegrityMode = [string]$settings.integrityMode
    }
    else {
        # Packaged builds ship hashes; enforce when file present unless overridden
        $path = Get-LocIntegrityPath
        $script:LocIntegrityMode = if (Test-Path $path) { "enforce" } else { "warn" }
    }

    $path = Get-LocIntegrityPath
    if (Test-Path $path) {
        try {
            $script:LocIntegrityStore = Get-Content $path -Raw | ConvertFrom-Json
        }
        catch {
            $script:LocIntegrityStore = $null
            Write-LocLog -Module "CORE" -Action "Integrity" -Level "WARN" -Message "Failed to load integrity store: $($_.Exception.Message)"
        }
    }
    else {
        $script:LocIntegrityStore = $null
    }
}

function Get-LocFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LocIntegrityStatus {
    $path = Get-LocIntegrityPath
    $moduleCount = 0
    $fileCount = 0
    if ($script:LocIntegrityStore -and $script:LocIntegrityStore.modules) {
        $mods = @($script:LocIntegrityStore.modules.PSObject.Properties)
        $moduleCount = $mods.Count
        foreach ($m in $mods) {
            if ($m.Value.files) {
                $fileCount += @($m.Value.files.PSObject.Properties).Count
            }
        }
    }
    return [PSCustomObject]@{
        Mode           = $script:LocIntegrityMode
        StorePresent   = [bool](Test-Path $path)
        StorePath      = $path
        ModulesHashed  = $moduleCount
        FilesHashed    = $fileCount
        GeneratedAt    = if ($script:LocIntegrityStore) { $script:LocIntegrityStore.generatedAt } else { $null }
        Version        = if ($script:LocIntegrityStore) { $script:LocIntegrityStore.version } else { $null }
    }
}

function Test-LocModuleIntegrity {
    param(
        [Parameter(Mandatory)][object]$Module,
        [string]$ScriptPath = ""
    )

    $result = [PSCustomObject]@{
        Ok       = $true
        Mode     = $script:LocIntegrityMode
        Message  = "OK"
        Expected = $null
        Actual   = $null
        Path     = $ScriptPath
    }

    if (-not $script:LocIntegrityStore -or -not $script:LocIntegrityStore.modules) {
        $result.Message = "No integrity store loaded"
        if ($script:LocIntegrityMode -eq "enforce") {
            $result.Ok = $false
            $result.Message = "Integrity store missing (enforce mode)"
        }
        return $result
    }

    $modId = $Module.Id.ToLower()
    $modEntry = $null
    foreach ($p in $script:LocIntegrityStore.modules.PSObject.Properties) {
        if ($p.Name.ToLower() -eq $modId) { $modEntry = $p.Value; break }
    }

    if (-not $modEntry) {
        $result.Message = "Module '$($Module.Id)' not in integrity store"
        if ($script:LocIntegrityMode -eq "enforce") {
            $result.Ok = $false
        }
        return $result
    }

    # Manifest hash
    if ($Module.ManifestPath -and (Test-Path $Module.ManifestPath)) {
        $actualManifest = Get-LocFileSha256 -Path $Module.ManifestPath
        $expectedManifest = $null
        if ($modEntry.manifestSha256) { $expectedManifest = [string]$modEntry.manifestSha256 }
        if ($expectedManifest -and $actualManifest -ne $expectedManifest.ToLowerInvariant()) {
            $result.Ok = $false
            $result.Expected = $expectedManifest
            $result.Actual = $actualManifest
            $result.Path = $Module.ManifestPath
            $result.Message = "Manifest hash mismatch for $($Module.Id)"
            return $result
        }
    }

    if ($ScriptPath) {
        $rel = $ScriptPath
        try {
            $root = [System.IO.Path]::GetFullPath($Module.Path).TrimEnd('\')
            $full = [System.IO.Path]::GetFullPath($ScriptPath)
            if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rel = $full.Substring($root.Length).TrimStart('\').Replace('\', '/')
            }
        }
        catch { }

        $expected = $null
        if ($modEntry.files) {
            foreach ($fp in $modEntry.files.PSObject.Properties) {
                if ($fp.Name -eq $rel -or $fp.Name.ToLower() -eq $rel.ToLower()) {
                    $expected = [string]$fp.Value
                    break
                }
            }
        }

        $actual = Get-LocFileSha256 -Path $ScriptPath
        $result.Actual = $actual
        $result.Expected = $expected
        $result.Path = $ScriptPath

        if (-not $expected) {
            $result.Message = "Script not in integrity store: $rel"
            if ($script:LocIntegrityMode -eq "enforce") {
                $result.Ok = $false
            }
            return $result
        }

        if ($actual -ne $expected.ToLowerInvariant()) {
            $result.Ok = $false
            $result.Message = "SHA-256 mismatch for $rel"
            return $result
        }
    }

    return $result
}

function New-LocIntegrityStore {
    param(
        [string]$ModulesPath = "",
        [string]$Version = ""
    )

    if (-not $ModulesPath) { $ModulesPath = Join-Path (Get-LocRoot) "modules" }
    if (-not $Version) {
        $v = Get-LocVersion
        $Version = if ($v) { [string]$v.version } else { "0.0.0" }
    }

    $modules = [ordered]@{}
    $manifests = Get-ChildItem -Path $ModulesPath -Filter "module.json" -Recurse -File -ErrorAction SilentlyContinue
    foreach ($man in $manifests) {
        $dir = Split-Path $man.FullName -Parent
        try {
            $json = Get-Content $man.FullName -Raw | ConvertFrom-Json
            $id = [string]$json.id
            if (-not $id) { continue }
            $files = [ordered]@{}
            Get-ChildItem -Path $dir -Recurse -File -Include "*.ps1", "*.json" -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring($dir.Length).TrimStart('\').Replace('\', '/')
                $files[$rel] = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            $modules[$id.ToLower()] = [ordered]@{
                id             = $id
                manifestSha256 = (Get-FileHash -Path $man.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                files          = $files
            }
        }
        catch { }
    }

    $store = [ordered]@{
        version     = $Version
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        algorithm   = "SHA256"
        modules     = $modules
    }

    $outPath = Get-LocIntegrityPath
    $outDir = Split-Path $outPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    ($store | ConvertTo-Json -Depth 8) | Set-Content -Path $outPath -Encoding UTF8
    $script:LocIntegrityStore = $store | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    return $outPath
}
