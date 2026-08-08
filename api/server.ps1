# api/server.ps1 - HttpListener static + API host
[CmdletBinding()]
param (
    [int]$Port = 8787,
    [string]$ModulesPath = "",
    [string]$DashboardPath = "",
    [string]$RootPath = "",
    [switch]$NoStatic,
    [string]$ProductMode = ""
)

$ErrorActionPreference = "Continue"

if (-not [string]::IsNullOrWhiteSpace($ProductMode)) {
    $ProductMode = $ProductMode.Trim().ToLowerInvariant()
    if ($ProductMode -notin @("desktop", "appliance")) {
        throw "ProductMode must be 'desktop' or 'appliance' (got: $ProductMode)"
    }
}
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
if ([string]::IsNullOrWhiteSpace($ModulesPath)) {
    $ModulesPath = Join-Path $RootPath "modules"
}
if ([string]::IsNullOrWhiteSpace($DashboardPath)) {
    $DashboardPath = Join-Path $RootPath "dashboard"
}

$ModulesPath = [System.IO.Path]::GetFullPath($ModulesPath)
$DashboardPath = [System.IO.Path]::GetFullPath($DashboardPath)
$RootPath = [System.IO.Path]::GetFullPath($RootPath)

# Load core via Engine facade (dot-source at script scope — required for PS scoping)
. (Join-Path $RootPath "core\Engine.ps1")
$coreFiles = @(Get-LocCoreEngineFiles -RootPath $RootPath)
foreach ($coreFile in $coreFiles) {
    . $coreFile
}

# Split routers must load before the thin router facade
$routerDir = Join-Path $PSScriptRoot "routers"
foreach ($name in @(
        "Builtins.ps1"
        "BuiltinsOps.ps1"
        "EventIntel.ps1"
        "ThreatRouter.ps1"
        "FleetRouter.ps1"
        "FleetRouterPackages.ps1"
    )) {
    $routerPath = Join-Path $routerDir $name
    if (-not (Test-Path -LiteralPath $routerPath)) {
        throw "Missing API router script: $routerPath"
    }
    . $routerPath
}
. (Join-Path $PSScriptRoot "router.ps1")

Initialize-LocSettings -RootPath $RootPath
Initialize-LocLogger -RootPath $RootPath
if (-not [string]::IsNullOrWhiteSpace($ProductMode)) {
    Initialize-LocLicense -ProductModeOverride $ProductMode
}
else {
    Initialize-LocLicense
}
Initialize-LocIntegrityManager
Initialize-LocFleetStore
Initialize-ModuleLoader -ModulesPath $ModulesPath
Start-LocTaskRunner
Initialize-LocEventStore
if (Test-LocEventIntelEnabled) {
    Start-LocEventIntelligence
}

$settings = Get-LocSettings
if ($Port -le 0) { $Port = [int]$settings.port }
$bindHost = if ($settings.bindHost) { [string]$settings.bindHost.Trim() } else { "localhost" }
if ([string]::IsNullOrWhiteSpace($bindHost)) { $bindHost = "localhost" }

$listenHosts = @(Resolve-LocHttpListenHosts -BindHost $bindHost)
$prefixes = @($listenHosts | ForEach-Object { "http://${_}:$Port/" })

# Appliance / API-only: skip dashboard static files (-NoStatic or productMode=appliance)
$script:LocNoStatic = [bool]$NoStatic
if (-not $script:LocNoStatic -and (Get-Command Test-LocApplianceMode -ErrorAction SilentlyContinue)) {
    $script:LocNoStatic = [bool](Test-LocApplianceMode)
}
# Explicit -ProductMode appliance also disables static even if settings say desktop
if (-not $script:LocNoStatic -and $ProductMode -eq "appliance") {
    $script:LocNoStatic = $true
}

$MimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
    ".map"  = "application/json"
}

$listener = New-Object System.Net.HttpListener
foreach ($prefix in $prefixes) {
    $listener.Prefixes.Add($prefix)
}
$script:LocHttpListener = $listener
$script:LocShutdownRequested = $false
$script:LocServerPort = $Port
$script:LocModulesPath = $ModulesPath
$script:LocDashboardPath = $DashboardPath
$script:LocRootPath = $RootPath

. (Join-Path $PSScriptRoot "ServerLifecycle.ps1")

try {
    $listener.Start()
    $prefixList = ($prefixes -join ", ")
    $modeNote = if ($script:LocNoStatic) { " noStatic=true" } else { "" }
    $listenMsg = "Listening on $prefixList (bindHost=$bindHost$modeNote)"
    Write-LocLog -Module "CORE" -Action "Server" -Level "SUCCESS" -Message $listenMsg
}
catch {
    $prefixList = ($prefixes -join ", ")
    $hint = @"
Failed to start HttpListener on $prefixList. $_

Hints:
- Stop any leftover LocalOps / powershell still holding port $Port (Get-NetTCPConnection -LocalPort $Port).
- Check URL reservations: netsh http show urlacl
- Overlapping reservations (e.g. http://+:${Port}/ vs a specific IP) cause 'conflicts with an existing registration'.
- For remote agents prefer bindHost=0.0.0.0 and put the LAN URL in fleetPublicUrl / agent -ServerUrl.
- Run elevated if HTTP.sys URL ACL denies access.
"@
    Write-Error $hint
    exit 1
}

function Serve-StaticFile {
    param([System.Net.HttpListenerContext]$Context, [string]$FilePath)

    $response = $Context.Response
    if (Test-Path $FilePath -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
        $contentType = if ($MimeTypes.ContainsKey($ext)) { $MimeTypes[$ext] } else { "application/octet-stream" }
        try {
            $bytes = [System.IO.File]::ReadAllBytes($FilePath)
            $response.ContentType = $contentType
            $response.ContentLength64 = $bytes.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        catch {
            $response.StatusCode = 500
        }
    }
    else {
        $response.StatusCode = 404
        $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes("404 - File Not Found")
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($notFoundBytes, 0, $notFoundBytes.Length)
    }
    $response.OutputStream.Close()
}


try {
    while ($listener.IsListening) {
        $async = $listener.BeginGetContext($null, $null)
        while (-not $async.IsCompleted) {
            if (Get-Command Pulse-LocEventIntelligence -ErrorAction SilentlyContinue) {
                Pulse-LocEventIntelligence
            }
            Start-Sleep -Milliseconds 100
        }
        $context = $listener.EndGetContext($async)
        $request = $context.Request
        $rawPath = $request.Url.AbsolutePath

        if ($request.HttpMethod -eq "OPTIONS") {
            $context.Response.Headers.Add("Access-Control-Allow-Origin", "*")
            $context.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
            $context.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, X-Loc-Agent, X-Loc-Timestamp, X-Loc-Signature")
            $context.Response.StatusCode = 204
            $context.Response.Close()
            continue
        }

        if ($rawPath.StartsWith("/api", [System.StringComparison]::OrdinalIgnoreCase)) {
            try {
                Invoke-LocRouter -Context $context
            }
            catch {
                Send-JsonResponse -Context $context -Success $false -Message "Routing Error: $($_.Exception.Message)" -StatusCode 500
            }
            continue
        }

        if ($script:LocNoStatic) {
            $context.Response.StatusCode = 404
            $msgBytes = [System.Text.Encoding]::UTF8.GetBytes("404 - Static UI disabled (appliance / NoStatic)")
            $context.Response.ContentType = "text/plain; charset=utf-8"
            $context.Response.ContentLength64 = $msgBytes.Length
            $context.Response.OutputStream.Write($msgBytes, 0, $msgBytes.Length)
            $context.Response.OutputStream.Close()
            continue
        }

        $sanitizedPath = $rawPath.TrimStart('/').Replace('/', '\')
        if ([string]::IsNullOrWhiteSpace($sanitizedPath)) { $sanitizedPath = "index.html" }

        $targetFilePath = [System.IO.Path]::GetFullPath((Join-Path $DashboardPath $sanitizedPath))
        if (-not (Test-SafePath -CandidatePath $targetFilePath -RootPath $DashboardPath)) {
            $context.Response.StatusCode = 403
            $context.Response.Close()
            continue
        }

        Serve-StaticFile -Context $context -FilePath $targetFilePath
    }
}
finally {
    if (Get-Command Stop-LocEventIntelligence -ErrorAction SilentlyContinue) {
        Stop-LocEventIntelligence
    }
    Stop-LocTaskRunner
    try {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
    catch { Write-Debug $_.Exception.Message }
    Write-LocLog -Module "CORE" -Action "Server" -Level "INFO" -Message "Server stopped"
    if ($script:LocShutdownRequested) {
        [Environment]::Exit(0)
    }
}
