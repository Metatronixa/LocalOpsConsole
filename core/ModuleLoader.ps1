# core/ModuleLoader.ps1 - Discover, validate, resolve depends, invoke modules

$script:LocModules = [ordered]@{}
$script:LocModuleErrors = @()
$script:LocModulesPath = $null

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
            $entry = [PSCustomObject]@{
                Id             = [string]$json.id
                Name           = [string]$json.name
                Version        = if ($json.version) { [string]$json.version } else { "1.0.0" }
                Icon           = if ($json.icon) { [string]$json.icon } else { "box" }
                Description    = if ($json.description) { [string]$json.description } else { "" }
                Order          = if ($null -ne $json.order) { [int]$json.order } else { 100 }
                Tier           = if ($null -ne $json.tier) { [int]$json.tier } else { 1 }
                Profiles       = if ($null -ne $json.profiles) { @($json.profiles | ForEach-Object { [string]$_ }) } else { @("power_user") }
                Depends        = @($json.depends | ForEach-Object { [string]$_ })
                Diagnostics    = @($json.diagnostics | ForEach-Object { [string]$_ })
                Actions        = @($json.actions | ForEach-Object { [string]$_ })
                RequiresAdmin  = @($json.requiresAdmin | ForEach-Object { [string]$_ })
                CacheSeconds   = @{}
                Path           = $moduleDir
                ManifestPath   = $file.FullName
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

function Find-ActionScript {
    param(
        [object]$Module,
        [ValidateSet("diagnostics", "actions")]
        [string]$Kind,
        [string]$ActionName
    )

    $dir = Join-Path $Module.Path $Kind
    if (-not (Test-Path $dir)) { return $null }

    $exact = Join-Path $dir "$ActionName.ps1"
    if (Test-Path $exact) { return $exact }

    $match = Get-ChildItem -Path $dir -Filter "*.ps1" -File |
        Where-Object { $_.BaseName -eq $ActionName -or $_.BaseName.ToLower() -eq $ActionName.ToLower() } |
        Select-Object -First 1

    if ($match) { return $match.FullName }
    return $null
}

function Invoke-LocModuleAction {
    param(
        [string]$ModuleId,
        [ValidateSet("diagnostics", "actions")]
        [string]$Kind,
        [string]$ActionName,
        [hashtable]$Params = @{},
        [bool]$ForceRefresh = $false
    )

    $mod = Get-LocModule -Id $ModuleId
    if (-not $mod) {
        return New-ApiResult -Success $false -Message "Module '$ModuleId' not found" -StatusCode 404
    }

    $list = if ($Kind -eq "diagnostics") { $mod.Diagnostics } else { $mod.Actions }
    $known = $list | Where-Object { $_.ToLower() -eq $ActionName.ToLower() }
    if (-not $known) {
        # Still allow file-based discovery if listed name casing differs
        $scriptPathProbe = Find-ActionScript -Module $mod -Kind $Kind -ActionName $ActionName
        if (-not $scriptPathProbe) {
            return New-ApiResult -Success $false -Message "Action '$Kind/$ActionName' not registered on module '$ModuleId'" -StatusCode 404
        }
    }

    $canonical = if ($known) { $known } else { $ActionName }
    $scriptPath = Find-ActionScript -Module $mod -Kind $Kind -ActionName $canonical
    if (-not $scriptPath) {
        return New-ApiResult -Success $false -Message "Script for '$ModuleId/$Kind/$ActionName' not found" -StatusCode 404
    }

    # Admin gate
    $needsAdmin = $mod.RequiresAdmin | Where-Object { $_.ToLower() -eq $canonical.ToLower() }
    if ($needsAdmin) {
        $denied = Require-Admin -ActionName "$($mod.Name)/$canonical"
        if ($denied) {
            Write-LocLog -Module $mod.Id -Action $canonical -Level "ERROR" -Message "Access Denied (requires admin)"
            return $denied
        }
    }

    # Cache (diagnostics only)
    $settings = Get-LocSettings
    $ttl = [int]$settings.cacheTtlSeconds
    if ($mod.CacheSeconds.ContainsKey($canonical)) {
        $ttl = [int]$mod.CacheSeconds[$canonical]
    }
    elseif ($mod.CacheSeconds.ContainsKey($ActionName)) {
        $ttl = [int]$mod.CacheSeconds[$ActionName]
    }

    $paramKey = ""
    if ($Params.Count -gt 0) {
        $paramKey = ($Params.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
    }
    $cacheKey = Get-CacheKey -Module $mod.Id -Kind $Kind -Action $canonical -ParamKey $paramKey

    if ($Kind -eq "diagnostics" -and $ttl -gt 0 -and -not $ForceRefresh) {
        $cached = Get-LocCache -Key $cacheKey
        if ($null -ne $cached) {
            Write-LocLog -Module $mod.Id -Action $canonical -Level "INFO" -Message "Cache hit"
            return $cached
        }
    }

    Write-LocLog -Module $mod.Id -Action $canonical -Level "INFO" -Message "Executing $Kind"

    try {
        # Ensure module libs (and dependency libs) are visible to the action script
        $libModules = @()
        foreach ($depId in @($mod.Depends)) {
            if ($depId) {
                $depMod = Get-LocModule -Id $depId
                if ($depMod) { $libModules += $depMod }
            }
        }
        $libModules += $mod
        foreach ($lm in $libModules) {
            $libDir = Join-Path $lm.Path "lib"
            if (Test-Path $libDir) {
                Get-ChildItem -Path $libDir -Filter "*.ps1" -File -ErrorAction SilentlyContinue | ForEach-Object {
                    . $_.FullName
                }
            }
        }

        # Bound splat: only params defined on script (AST parse — reliable for .ps1 files)
        $splat = @{}
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $scriptParams = @()
        if ($ast -and $ast.ParamBlock) {
            $scriptParams = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        }
        foreach ($key in @($Params.Keys)) {
            $match = $scriptParams | Where-Object { $_.ToLower() -eq $key.ToLower() } | Select-Object -First 1
            if ($match) { $splat[$match] = $Params[$key] }
        }

        # Dot-source so the script can call helpers loaded above (& would hide them)
        $rawOutput = @(. $scriptPath @splat)
        $result = $rawOutput | Where-Object {
            $null -ne $_ -and ($_.PSObject.Properties.Name -contains 'Success')
        } | Select-Object -Last 1

        if ($null -eq $result) {
            if ($rawOutput.Count -eq 0) {
                $result = New-ApiResult -Success $true -Message "Executed" -Data @{}
            }
            else {
                $data = if ($rawOutput.Count -eq 1) { $rawOutput[0] } else { @($rawOutput) }
                $result = New-ApiResult -Success $true -Message "Executed" -Data $data
            }
        }
        elseif ($result -is [hashtable]) {
            $dataVal = $result.Data
            if ($null -eq $dataVal) { $dataVal = @{} }
            $result = New-ApiResult -Success ([bool]$result.Success) -Message ([string]$result.Message) -Data $dataVal
        }
        else {
            $statusCode = 200
            if ($result.PSObject.Properties.Name -contains 'StatusCode' -and $null -ne $result.StatusCode) {
                $statusCode = [int]@($result.StatusCode)[0]
            }
            # Assign Data without $() — that subexpression unwraps single-element arrays
            $dataVal = $result.Data
            if ($null -eq $dataVal) { $dataVal = @{} }
            $result = New-ApiResult `
                -Success ([bool]@($result.Success)[0]) `
                -Message ([string]@($result.Message)[0]) `
                -Data $dataVal `
                -StatusCode $statusCode
        }

        if ($result.Success) {
            Write-LocLog -Module $mod.Id -Action $canonical -Level "SUCCESS" -Message $result.Message
            if ($Kind -eq "diagnostics" -and $ttl -gt 0) {
                Set-LocCache -Key $cacheKey -Value $result -TtlSeconds $ttl
            }
            if ($Kind -eq "actions") {
                Clear-LocCache -Prefix ("{0}:" -f $mod.Id.ToLower())
            }
        }
        else {
            Write-LocLog -Module $mod.Id -Action $canonical -Level "ERROR" -Message $result.Message
        }

        return $result
    }
    catch {
        Write-LocLog -Module $mod.Id -Action $canonical -Level "ERROR" -Message $_.Exception.Message
        return New-ApiResult -Success $false -Message "Script Error: $($_.Exception.Message)" -StatusCode 500
    }
}
