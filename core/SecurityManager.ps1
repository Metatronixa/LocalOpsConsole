# core/SecurityManager.ps1 - Pre-execution security gate for modules

function Invoke-LocSecurityGate {
    param(
        [Parameter(Mandatory)][object]$Module,
        [Parameter(Mandatory)][ValidateSet("diagnostics", "actions")][string]$Kind,
        [Parameter(Mandatory)][string]$ActionName,
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$Params = @{}
    )

    $null = $Kind
    $gate = [PSCustomObject]@{
        Ok         = $true
        Message    = "OK"
        StatusCode = 200
        Data       = @{}
        Splat      = @{}
    }

    # 1. Manifest validation
    if (-not $Module.Id -or -not $Module.ManifestPath -or -not (Test-Path $Module.ManifestPath)) {
        $gate.Ok = $false
        $gate.Message = "Module manifest invalid or missing"
        $gate.StatusCode = 400
        Invoke-LocSecurityFailure -Module $Module -ActionName $ActionName -Reason $gate.Message
        return $gate
    }

    # 2. Integrity (SHA-256)
    if (Get-Command Test-LocModuleIntegrity -ErrorAction SilentlyContinue) {
        $integrity = Test-LocModuleIntegrity -Module $Module -ScriptPath $ScriptPath
        if (-not $integrity.Ok) {
            $gate.Ok = $false
            $gate.Message = "Integrity check failed: $($integrity.Message)"
            $gate.StatusCode = 403
            $gate.Data = @{
                Expected = $integrity.Expected
                Actual   = $integrity.Actual
                Path     = $integrity.Path
                Mode     = $integrity.Mode
            }
            Invoke-LocSecurityFailure -Module $Module -ActionName $ActionName -Reason $gate.Message -Data $gate.Data
            return $gate
        }
        elseif ($integrity.Message -ne "OK" -and $integrity.Mode -eq "warn") {
            Write-LocLog -Module "SECURITY" -Action $ActionName -Level "WARN" -Message "Integrity warn: $($integrity.Message)"
        }
    }

    # 3. Permission / elevation
    $denied = Assert-LocPermission -Module $Module -ActionName $ActionName
    if ($denied) {
        $gate.Ok = $false
        $gate.Message = $denied.Message
        $gate.StatusCode = 403
        $gate.Data = $denied.Data
        Invoke-LocSecurityFailure -Module $Module -ActionName $ActionName -Reason $gate.Message -Severity "Warning"
        return $gate
    }

    # 4. Dependencies
    $deps = Test-LocModuleDependencies -Module $Module
    if (-not $deps.Ok) {
        Write-LocLog -Module "SECURITY" -Action $ActionName -Level "WARN" -Message $deps.Message
        # Soft-fail: allow execution with warning (matches prior ModuleLoader behavior)
    }

    # 5. Parameter validation
    $paramCheck = Test-LocActionParameters -ScriptPath $ScriptPath -Params $Params
    $gate.Splat = $paramCheck.Splat
    if (-not $paramCheck.Ok) {
        $gate.Ok = $false
        $gate.Message = $paramCheck.Message
        $gate.StatusCode = 400
        Invoke-LocSecurityFailure -Module $Module -ActionName $ActionName -Reason $gate.Message
        return $gate
    }

    # 6. Path jail — script must live under module directory
    if (-not (Test-SafePath -CandidatePath $ScriptPath -RootPath $Module.Path)) {
        $gate.Ok = $false
        $gate.Message = "Script path escapes module directory"
        $gate.StatusCode = 403
        Invoke-LocSecurityFailure -Module $Module -ActionName $ActionName -Reason $gate.Message -Severity "Critical"
        return $gate
    }

    return $gate
}

function Invoke-LocSecurityFailure {
    param(
        [object]$Module,
        [string]$ActionName,
        [string]$Reason,
        [string]$Severity = "Critical",
        [hashtable]$Data = @{}
    )

    Write-LocLog -Module "SECURITY" -Action $ActionName -Level "ERROR" -Message $Reason

    if (Get-Command New-LocIncident -ErrorAction SilentlyContinue) {
        try {
            $title = "Security gate blocked: $($Module.Id)/$ActionName"
            $evt = [PSCustomObject]@{
                Source   = "SecurityManager"
                EventID  = 9001
                Severity = $Severity
                Message  = $Reason
                Data     = $Data
            }
            New-LocIncident -Title $title -Category "Security" -Severity $Severity -Score $(if ($Severity -eq "Critical") { 90 } else { 60 }) `
                -CorrelationKey ("security-gate:{0}:{1}" -f $Module.Id, $ActionName) -Event $evt -RuleId "security-gate" | Out-Null
        }
        catch {
            Write-LocLog -Module "SECURITY" -Action "Incident" -Level "WARN" -Message "Failed to open security incident: $($_.Exception.Message)"
        }
    }
}
