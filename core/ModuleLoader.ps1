# core/ModuleLoader.ps1 - Discover, validate, and resolve module manifests

$script:LocModules = [ordered]@{}
$script:LocModuleErrors = @()
$script:LocModulesPath = $null

function Convert-LocModuleManifestList {
    param([object]$Items)
    $ids = [System.Collections.ArrayList]::new()
    $meta = [ordered]@{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if ($item -is [string] -or $item.GetType().IsValueType) {
            $id = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($id)) { [void]$ids.Add($id) }
            continue
        }
        $id = $null
        if ($item -is [hashtable]) {
            if ($item.ContainsKey('id')) { $id = [string]$item['id'] }
        }
        elseif ($item.PSObject.Properties['id']) {
            $id = [string]$item.id
        }
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            [void]$ids.Add($id)
            $meta[$id] = $item
        }
    }
    return [PSCustomObject]@{
        Ids  = @($ids)
        Meta = $meta
    }
}

function Initialize-ModuleLoader {
    param([string]$ModulesPath)

    $script:LocModulesPath = $ModulesPath
    $script:LocModules = [ordered]@{}
    $script:LocModuleErrors = @()

    if (-not (Test-Path $ModulesPath)) {
        Write-LocLog -Module "CORE" -Action "ModuleLoader" -Level "ERROR" -Message "Modules path not found: $ModulesPath"
        return
    }

    $manifests = Get-ChildItem -Path $ModulesPath -Filter "module.json" -Recurse -File -ErrorAction SilentlyContinue
    $raw = @()

    foreach ($file in $manifests) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $moduleDir = Split-Path $file.FullName -Parent
            $diagParsed = Convert-LocModuleManifestList -Items $json.diagnostics
            $actParsed = Convert-LocModuleManifestList -Items $json.actions
            $entry = [PSCustomObject]@{
                Id              = [string]$json.id
                Name            = [string]$json.name
                Version         = if ($json.version) { [string]$json.version } else { "1.0.0" }
                Icon            = if ($json.icon) { [string]$json.icon } else { "box" }
                Description     = if ($json.description) { [string]$json.description } else { "" }
                Order           = if ($null -ne $json.order) { [int]$json.order } else { 100 }
                Tier            = if ($null -ne $json.tier) { [int]$json.tier } else { 1 }
                Profiles        = if ($null -ne $json.profiles) { @($json.profiles | ForEach-Object { [string]$_ }) } else { @("power_user") }
                Depends         = @($json.depends | ForEach-Object { [string]$_ })
                Diagnostics     = @($diagParsed.Ids)
                Actions         = @($actParsed.Ids)
                DiagnosticsMeta = $diagParsed.Meta
                ActionsMeta     = $actParsed.Meta
                RequiresAdmin   = @($json.requiresAdmin | ForEach-Object { [string]$_ })
                Hidden          = if ($null -ne $json.hidden) { [bool]$json.hidden } else { $false }
                CacheSeconds    = @{}
                Capabilities    = if ($null -ne $json.capabilities) { @($json.capabilities | ForEach-Object { [string]$_ }) } else { @() }
                RequiredEdition = if ($json.requiredEdition) { ([string]$json.requiredEdition).Trim().ToLowerInvariant() } else { "community" }
                Path            = $moduleDir
                ManifestPath    = $file.FullName
            }

            if ($json.cacheSeconds) {
                foreach ($p in $json.cacheSeconds.PSObject.Properties) {
                    $entry.CacheSeconds[$p.Name] = [int]$p.Value
                }
            }

            if ([string]::IsNullOrWhiteSpace($entry.Id)) {
                throw "module.json missing id at $($file.FullName)"
            }

            $raw += $entry
        }
        catch {
            $script:LocModuleErrors += $_.Exception.Message
            Write-LocLog -Module "CORE" -Action "ModuleLoader" -Level "ERROR" -Message $_.Exception.Message
        }
    }

    # Topological sort by depends
    $remaining = [System.Collections.ArrayList]@($raw)
    $sorted = [System.Collections.ArrayList]::new()
    $guard = 0

    while ($remaining.Count -gt 0 -and $guard -lt 200) {
        $guard++
        $progress = $false
        $loadedIds = @($sorted | ForEach-Object { $_.Id.ToLower() })

        for ($i = 0; $i -lt $remaining.Count; $i++) {
            $mod = $remaining[$i]
            $deps = @($mod.Depends | Where-Object { $_ })
            $ready = $true
            foreach ($d in $deps) {
                if ($loadedIds -notcontains $d.ToLower()) {
                    # Allow missing deps as warning but still load
                    $exists = $raw | Where-Object { $_.Id -eq $d }
                    if ($exists) { $ready = $false; break }
                }
            }
            if ($ready) {
                [void]$sorted.Add($mod)
                $remaining.RemoveAt($i)
                $progress = $true
                break
            }
        }

        if (-not $progress) {
            foreach ($left in @($remaining)) {
                Write-LocLog -Module "CORE" -Action "ModuleLoader" -Level "WARN" -Message "Dependency cycle or unresolved deps for $($left.Id); loading anyway"
                [void]$sorted.Add($left)
            }
            $remaining.Clear()
        }
    }

    foreach ($mod in ($sorted | Sort-Object Order, Name)) {
        $script:LocModules[$mod.Id.ToLower()] = $mod
        # Dot-source lib helpers
        $libDir = Join-Path $mod.Path "lib"
        if (Test-Path $libDir) {
            Get-ChildItem -Path $libDir -Filter "*.ps1" -File | ForEach-Object {
                . $_.FullName
            }
        }
    }

    Write-LocLog -Module "CORE" -Action "ModuleLoader" -Level "SUCCESS" -Message ("Loaded {0} module(s)" -f $script:LocModules.Count)
}

function Get-LocModules {
    return @($script:LocModules.Values)
}

function Get-LocModule {
    param([string]$Id)
    $key = $Id.ToLower()
    if ($script:LocModules.Keys -contains $key) {
        return $script:LocModules[$key]
    }
    return $null
}

function Get-LocModuleErrors {
    return @($script:LocModuleErrors)
}
