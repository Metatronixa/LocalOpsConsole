# core/PermissionManager.ps1 - Elevation and capability validation

function Test-LocActionRequiresAdmin {
    param(
        [Parameter(Mandatory)][object]$Module,
        [Parameter(Mandatory)][string]$ActionName
    )
    $needs = @($Module.RequiresAdmin | Where-Object { $_.ToLower() -eq $ActionName.ToLower() })
    return ($needs.Count -gt 0)
}

function Test-LocElevation {
    param(
        [Parameter(Mandatory)][object]$Module,
        [Parameter(Mandatory)][string]$ActionName
    )

    $result = [PSCustomObject]@{
        Ok            = $true
        RequiresAdmin = $false
        IsAdmin       = (Test-IsAdmin)
        Message       = "OK"
    }

    if (Test-LocActionRequiresAdmin -Module $Module -ActionName $ActionName) {
        $result.RequiresAdmin = $true
        if (-not $result.IsAdmin) {
            $result.Ok = $false
            $result.Message = "$($Module.Name)/$ActionName requires elevated (Administrator) privileges."
        }
    }
    return $result
}

function Test-LocModuleDependencies {
    param([Parameter(Mandatory)][object]$Module)

    $missing = @()
    foreach ($dep in @($Module.Depends)) {
        if (-not $dep) { continue }
        $depMod = Get-LocModule -Id $dep
        if (-not $depMod) { $missing += $dep }
    }

    return [PSCustomObject]@{
        Ok      = ($missing.Count -eq 0)
        Missing = $missing
        Message = if ($missing.Count -eq 0) { "OK" } else { "Missing dependencies: $($missing -join ', ')" }
    }
}

function Test-LocActionParameters {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$Params = @{}
    )

    $result = [PSCustomObject]@{
        Ok           = $true
        Message      = "OK"
        AllowedKeys  = @()
        UnknownKeys  = @()
        Splat        = @{}
    }

    if (-not (Test-Path $ScriptPath)) {
        $result.Ok = $false
        $result.Message = "Script not found"
        return $result
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    $scriptParams = @()
    if ($ast -and $ast.ParamBlock) {
        $scriptParams = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }
    $result.AllowedKeys = $scriptParams

    $splat = @{}
    $unknown = @()
    foreach ($key in @($Params.Keys)) {
        $match = $scriptParams | Where-Object { $_.ToLower() -eq $key.ToLower() } | Select-Object -First 1
        if ($match) {
            $splat[$match] = $Params[$key]
        }
        else {
            $unknown += $key
        }
    }
    $result.Splat = $splat
    $result.UnknownKeys = $unknown
    # Unknown keys are stripped (safe); do not fail — preserves prior behavior
    return $result
}

function Assert-LocPermission {
    param(
        [Parameter(Mandatory)][object]$Module,
        [Parameter(Mandatory)][string]$ActionName
    )

    $elev = Test-LocElevation -Module $Module -ActionName $ActionName
    if (-not $elev.Ok) {
        return New-ApiResult -Success $false -Message $elev.Message -StatusCode 403 -Data @{
            RequiresAdmin = $true
            IsAdmin       = $elev.IsAdmin
        }
    }
    return $null
}
