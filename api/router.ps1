# api/router.ps1 - Thin /api/v1 router

function Invoke-LocRouter {
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context
    )

    $request = $Context.Request
    $segments = @($request.Url.AbsolutePath.Trim('/').Split('/') | Where-Object { $_ })

    # Expect api / v1 / ...
    if ($segments.Count -lt 2 -or $segments[0].ToLower() -ne "api" -or $segments[1].ToLower() -ne "v1") {
        Send-JsonResponse -Context $Context -Success $false -Message "API requires /api/v1/ prefix" -StatusCode 400
        return
    }

    $resource = if ($segments.Count -ge 3) { $segments[2].ToLower() } else { "" }

    # Built-in: health
    if ($resource -eq "health") {
        $ver = Get-LocVersion
        $mods = Get-LocModules
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $caption = if ($os) { $os.Caption } else { $env:OS }
        $build = if ($os) { $os.Version } else { "" }

        $data = [PSCustomObject]@{
            Version       = $ver.version
            Name          = $ver.name
            Admin         = Test-IsAdmin
            LoadedModules = $mods.Count
            ModuleErrors  = @(Get-LocModuleErrors)
            PowerShell    = $PSVersionTable.PSVersion.ToString()
            Windows       = ("{0} ({1})" -f $caption, $build).Trim()
            Status        = if ((Get-LocModuleErrors).Count -eq 0) { "Healthy" } else { "Degraded" }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "OK" -Data $data
        return
    }

    # Built-in: modules
    if ($resource -eq "modules") {
        $mods = Get-LocModules | ForEach-Object {
            [PSCustomObject]@{
                id            = $_.Id
                name          = $_.Name
                version       = $_.Version
                icon          = $_.Icon
                description   = $_.Description
                order         = $_.Order
                tier          = $_.Tier
                profiles      = $_.Profiles
                depends       = $_.Depends
                diagnostics   = $_.Diagnostics
                actions       = $_.Actions
                requiresAdmin = $_.RequiresAdmin
            }
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Modules loaded" -Data @($mods)
        return
    }

    # Built-in: logs/tail
    if ($resource -eq "logs") {
        $lines = 100
        if ($request.QueryString["lines"]) {
            [void][int]::TryParse($request.QueryString["lines"], [ref]$lines)
        }
        $tail = Get-ConsoleFeed -Lines $lines
        Send-JsonResponse -Context $Context -Success $true -Message "Log tail" -Data @($tail)
        return
    }

    # Built-in: telemetry (lazy refresh on read - never blocks accept loop)
    if ($resource -eq "telemetry") {
        $force = $false
        $forceRaw = $request.QueryString["force"]
        if ($forceRaw -and ($forceRaw -eq "1" -or $forceRaw -match '^(?i)true|yes$')) {
            $force = $true
        }
        Send-JsonResponse -Context $Context -Success $true -Message "Telemetry snapshot" -Data (Get-LocTelemetrySnapshot -Force $force)
        return
    }

    # Built-in: updates/check | updates/apply
    if ($resource -eq "updates") {
        $sub = if ($segments.Count -ge 4) { $segments[3].ToLower() } else { "check" }
        if ($sub -eq "check") {
            $result = Test-LocUpdate
            $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        if ($sub -eq "apply") {
            if ($request.HttpMethod -ne "POST") {
                Send-JsonResponse -Context $Context -Success $false -Message "Apply requires POST" -StatusCode 405
                return
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
            catch { }
            $result = if ($force) { Apply-LocUpdate -Force } else { Apply-LocUpdate }
            $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
            Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
            return
        }
        Send-JsonResponse -Context $Context -Success $false -Message "Use /api/v1/updates/check or /api/v1/updates/apply" -StatusCode 400
        return
    }

    # Module route: /api/v1/{module}/{diagnostics|actions}/{name}
    if ($segments.Count -lt 5) {
        Send-JsonResponse -Context $Context -Success $false -Message "Invalid endpoint. Use /api/v1/{module}/{diagnostics|actions}/{name}" -StatusCode 400
        return
    }

    $moduleId = $segments[2]
    $kind = $segments[3].ToLower()
    $actionName = $segments[4]

    if ($kind -ne "diagnostics" -and $kind -ne "actions") {
        Send-JsonResponse -Context $Context -Success $false -Message "Kind must be 'diagnostics' or 'actions'" -StatusCode 400
        return
    }

    $params = @{}
    $forceRefresh = $false

    if ($request.HttpMethod -eq "POST") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
        $body = $reader.ReadToEnd()
        if ($body) {
            try {
                $obj = $body | ConvertFrom-Json
                foreach ($p in $obj.PSObject.Properties) {
                    $params[$p.Name] = $p.Value
                }
            }
            catch {
                Send-JsonResponse -Context $Context -Success $false -Message "Invalid JSON body" -StatusCode 400
                return
            }
        }
    }
    else {
        foreach ($key in $request.QueryString.AllKeys) {
            if ($key) {
                if ($key.ToLower() -eq "refresh" -and $request.QueryString[$key] -in @("1", "true", "yes")) {
                    $forceRefresh = $true
                }
                else {
                    $params[$key] = $request.QueryString[$key]
                }
            }
        }
    }

    if ($kind -eq "actions" -and $request.HttpMethod -ne "POST") {
        Send-JsonResponse -Context $Context -Success $false -Message "Actions require POST" -StatusCode 405
        return
    }

    $result = Invoke-LocModuleAction -ModuleId $moduleId -Kind $kind -ActionName $actionName -Params $params -ForceRefresh $forceRefresh
    $status = if ($result.PSObject.Properties['StatusCode']) { [int]$result.StatusCode } else { 200 }
    Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
}
