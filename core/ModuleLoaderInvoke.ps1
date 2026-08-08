# core/ModuleLoaderInvoke.ps1 - Resolve and execute module diagnostics/actions

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

    # Security gate: manifest, integrity, elevation, deps, params, path jail
    $gate = Invoke-LocSecurityGate -Module $mod -Kind $Kind -ActionName $canonical -ScriptPath $scriptPath -Params $Params
    if (-not $gate.Ok) {
        Write-LocLog -Module $mod.Id -Action $canonical -Level "ERROR" -Message $gate.Message
        return New-ApiResult -Success $false -Message $gate.Message -StatusCode $gate.StatusCode -Data $gate.Data
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

        $splat = if ($gate.Splat) { $gate.Splat } else { @{} }

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
