# api/routers/Builtins.ps1 - health/license/modules/logs/telemetry/shutdown/updates/integrity
# Returns $true when the request was fully handled; $false to fall through (updates/syncme module routes).

function Invoke-LocBuiltinRouter {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments,
        [string]$Method,
        [string]$Resource
    )

    $request = $Context.Request

    # Built-in: health (must stay cheap — readiness probe for launcher / Restart)
    if ($Resource -eq "health") {
        $ver = Get-LocVersion
        $mods = Get-LocModules
        if (-not $script:LocHealthOsCaption) {
            $script:LocHealthOsCaption = if ($env:OS) { [string]$env:OS } else { "Windows" }
            $script:LocHealthOsBuild = [Environment]::OSVersion.Version.ToString()
        }

        $lic = $null
        if (Get-Command Get-LocLicenseSummary -ErrorAction SilentlyContinue) {
            $lic = Get-LocLicenseSummary
        }

        $data = [PSCustomObject]@{
            Version       = $ver.version
            Name          = $ver.name
            Admin         = Test-IsAdmin
            LoadedModules = $mods.Count
            ModuleErrors  = @(Get-LocModuleErrors)
            PowerShell    = $PSVersionTable.PSVersion.ToString()
            Windows       = ("{0} ({1})" -f $script:LocHealthOsCaption, $script:LocHealthOsBuild).Trim()
            Status        = if ((Get-LocModuleErrors).Count -eq 0) { "Healthy" } else { "Degraded" }
            Edition       = if ($lic) { [string]$lic.Edition } else { "Community" }
            ProductMode   = if ($lic) { [string]$lic.ProductMode } else { "desktop" }
            Sku           = if ($lic) { [string]$lic.Sku } else { "community" }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "OK" -Data $data
        return $true
    }

    # Built-in: license status (safe summary — no raw key)
    if ($Resource -eq "license") {
        if ($Method -ne "GET") {
            Send-JsonResponse -Context $Context -Success $false -Message "License requires GET" -StatusCode 405
            return $true
        }
        $summary = if (Get-Command Get-LocLicenseSummary -ErrorAction SilentlyContinue) {
            Get-LocLicenseSummary
        }
        else {
            [PSCustomObject]@{
                Valid = $true; Edition = "Community"; Sku = "community"
                ProductMode = "desktop"; LicensedTo = $null; ExpiresAt = $null
                AgentLimit = $null; Source = "community"; Message = "LicenseManager unavailable"
            }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "License status" -Data $summary
        return $true
    }

    # Built-in: modules
    if ($Resource -eq "modules") {
        $mods = Get-LocModules | ForEach-Object {
            [PSCustomObject]@{
                id              = $_.Id
                name            = $_.Name
                version         = $_.Version
                icon            = $_.Icon
                description     = $_.Description
                order           = $_.Order
                tier            = $_.Tier
                requiredEdition = if ($_.RequiredEdition) { $_.RequiredEdition } else { "community" }
                # Wrap as ArrayList so ConvertTo-Json keeps single-item arrays as JSON arrays
                profiles        = [System.Collections.ArrayList]@($_.Profiles)
                depends         = [System.Collections.ArrayList]@($_.Depends)
                diagnostics     = [System.Collections.ArrayList]@($_.Diagnostics)
                actions         = [System.Collections.ArrayList]@($_.Actions)
                requiresAdmin   = [System.Collections.ArrayList]@($_.RequiresAdmin)
                hidden          = $_.Hidden
                capabilities    = [System.Collections.ArrayList]@(if ($_.Capabilities) { $_.Capabilities } else { @() })
            }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Modules loaded" -Data @($mods)
        return $true
    }

    # Built-in: logs/tail
    if ($Resource -eq "logs") {
        $lines = 100
        if ($request.QueryString["lines"]) {
            [void][int]::TryParse($request.QueryString["lines"], [ref]$lines)
        }
        $tail = Get-ConsoleFeed -Lines $lines
        Send-JsonResponse -Context $Context -Success $true -Message "Log tail" -Data @($tail)
        return $true
    }

    # Built-in: telemetry (lazy refresh on read - never blocks accept loop)
    if ($Resource -eq "telemetry") {
        $force = $false
        $forceRaw = $request.QueryString["force"]
        if ($forceRaw -and ($forceRaw -eq "1" -or $forceRaw -match '^(?i)true|yes$')) {
            $force = $true
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Telemetry snapshot" -Data (Get-LocTelemetrySnapshot -Force $force)
        return $true
    }

    # Built-in: shutdown (stops HttpListener; detached server exits)
    if ($Resource -eq "shutdown") {
        if ($Method -ne "POST") {
            Send-JsonResponse -Context $Context -Success $false -Message "Shutdown requires POST" -StatusCode 405
            return $true
        }
        Write-LocLog -Module "CORE" -Action "Shutdown" -Level "WARN" -Message "Shutdown requested via API"
        Send-JsonResponse -Context $Context -Success $true -Message "Shutting down" -Data @{ Stopping = $true }
        if (Get-Command Request-LocShutdown -ErrorAction SilentlyContinue) {
            Request-LocShutdown
        }
        return $true
    }

    # Built-in: restart (relaunch api/server.ps1 from this elevated process — no UAC / start.ps1)
    if ($Resource -eq "restart") {
        if ($Method -ne "POST") {
            Send-JsonResponse -Context $Context -Success $false -Message "Restart requires POST" -StatusCode 405
            return $true
        }
        Write-LocLog -Module "CORE" -Action "Restart" -Level "WARN" -Message "Restart requested via API"
        try {
            if (-not (Get-Command Request-LocServerRelaunch -ErrorAction SilentlyContinue)) {
                Send-JsonResponse -Context $Context -Success $false -Message "Restart helper unavailable" -StatusCode 500
                return $true
            }
            Request-LocServerRelaunch
        }
        catch {
            Send-JsonResponse -Context $Context -Success $false -Message ("Restart schedule failed: {0}" -f $_.Exception.Message) -StatusCode 500
            return $true
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Restarting" -Data @{ Restarting = $true }
        if (Get-Command Request-LocShutdown -ErrorAction SilentlyContinue) {
            Request-LocShutdown
        }
        return $true
    }

    # Built-in: updates/check | updates/apply
    if ($Resource -eq "updates") {
        $sub = if ($Segments.Count -ge 4) { $Segments[3].ToLower() } else { "check" }
        if ($sub -eq "check") {
            $result = Test-LocUpdate
            $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return $true
        }
        if ($sub -eq "apply") {
            if ($Method -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Apply requires POST" -StatusCode 405
                return $true
            }
            $force = $false
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $body = $reader.ReadToEnd()
                if ($body) {
                    $obj = $body | ConvertFrom-Json
                    if ($obj.Force) { $force = [bool]$obj.Force }
                }
            }
            catch { Write-Debug $_.Exception.Message }
            $result = if ($force) { Apply-LocUpdate -Force } else { Apply-LocUpdate }
            $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return $true
        }
        # Fall through to Windows Updates module (diagnostics/actions)
        return $false
    }

    # Built-in: integrity status
    if ($Resource -eq "integrity") {
        $sub = if ($Segments.Count -ge 4) { $Segments[3].ToLower() } else { "status" }
        if ($sub -eq "status") {
            Send-JsonResponse -Context $Context -Success $true -Message "Integrity status" -Data (Get-LocIntegrityStatus)
            return $true
        }
        Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/integrity/status" -StatusCode 400
        return $true
    }

    if ($Resource -eq "automation") {
        return (Invoke-LocBuiltinAutomation -Context $Context -Segments $Segments -Method $Method -Request $request)
    }

    if ($Resource -eq "settings") {
        return (Invoke-LocBuiltinSettings -Context $Context -Segments $Segments -Method $Method -Request $request)
    }

    if ($Resource -eq "syncme") {
        return (Invoke-LocBuiltinSyncMe -Context $Context -Segments $Segments -Method $Method -Request $request)
    }

    return $false
}
