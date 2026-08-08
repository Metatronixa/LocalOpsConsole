# api/router.ps1 - Thin /api/v1 router (sibling files loaded by server.ps1)

function Read-LocRequestBody {
    param([System.Net.HttpListenerRequest]$Request)
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    return $reader.ReadToEnd()
}

function Parse-LocJsonBody {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @{} }
    try {
        $obj = $Body | ConvertFrom-Json
        return ConvertTo-Hashtable -InputObject $obj
    }
    catch {
        return $null
    }
}

function Invoke-LocRouter {
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context
    )

    $request = $Context.Request
    $method = $request.HttpMethod.ToUpperInvariant()
    $segments = @($request.Url.AbsolutePath.Trim('/').Split('/') | Where-Object { $_ })

    # Expect api / v1 / ...
    if ($segments.Count -lt 2 -or $segments[0].ToLower() -ne "api" -or $segments[1].ToLower() -ne "v1") {
        Send-JsonResponse -Context $Context -Success $false -Message "API requires /api/v1/ prefix" -StatusCode 400
        return
    }

    $resource = if ($segments.Count -ge 3) { $segments[2].ToLower() } else { "" }

    if (Invoke-LocBuiltinRouter -Context $Context -Segments $segments -Method $method -Resource $resource) {
        return
    }

    # Built-in: Event Intelligence
    if ($resource -in @("events", "alerts", "incidents", "timeline", "rules", "notifications", "security-score", "health-score", "heatmap", "event-intel")) {
        Invoke-LocEventIntelRouter -Context $Context -Segments $segments
        return
    }

    # Built-in: fleet RMM (before module routes)
    if ($resource -eq "fleet") {
        $fleetSub = if ($segments.Count -ge 4) { $segments[3].ToLower() } else { "" }
        if ($fleetSub -eq "threat-telemetry") {
            Invoke-LocThreatTelemetryRoute -Context $Context -Segments $segments
            return
        }
        Invoke-LocFleetRouter -Context $Context -Segments $segments
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
