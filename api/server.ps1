# api/server.ps1 - HttpListener static + API host
[CmdletBinding()]
param (
    [int]$Port = 8787,
    [string]$ModulesPath = "",
    [string]$DashboardPath = "",
    [string]$RootPath = ""
)

$ErrorActionPreference = "Continue"

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

# Load core
. (Join-Path $RootPath "core\Response.ps1")
. (Join-Path $RootPath "core\Security.ps1")
. (Join-Path $RootPath "core\Settings.ps1")
. (Join-Path $RootPath "core\Logger.ps1")
. (Join-Path $RootPath "core\Cache.ps1")
. (Join-Path $RootPath "core\Console.ps1")
. (Join-Path $RootPath "core\ModuleLoader.ps1")
. (Join-Path $RootPath "core\TaskRunner.ps1")
. (Join-Path $RootPath "core\Updater.ps1")
. (Join-Path $RootPath "core\FleetStore.ps1")
. (Join-Path $RootPath "core\FleetAuth.ps1")
. (Join-Path $RootPath "core\Fleet.ps1")
. (Join-Path $PSScriptRoot "router.ps1")

Initialize-LocSettings -RootPath $RootPath
Initialize-LocLogger -RootPath $RootPath
Initialize-LocFleetStore
Initialize-ModuleLoader -ModulesPath $ModulesPath
Start-LocTaskRunner

$settings = Get-LocSettings
if ($Port -le 0) { $Port = [int]$settings.port }
$bindHost = if ($settings.bindHost) { $settings.bindHost } else { "localhost" }

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
$prefix = "http://${bindHost}:$Port/"
$listener.Prefixes.Add($prefix)
$script:LocHttpListener = $listener
$script:LocShutdownRequested = $false

function Request-LocShutdown {
    $script:LocShutdownRequested = $true
    try {
        if ($script:LocHttpListener -and $script:LocHttpListener.IsListening) {
            $script:LocHttpListener.Stop()
        }
    }
    catch { }
}

try {
    $listener.Start()
    Write-LocLog -Module "CORE" -Action "Server" -Level "SUCCESS" -Message "Listening on $prefix"
}
catch {
    Write-Error "Failed to start HttpListener on $prefix. $_"
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
            Start-Sleep -Milliseconds 100
        }
        $context = $listener.EndGetContext($async)
        $request = $context.Request
        $rawPath = $request.Url.AbsolutePath

        if ($request.HttpMethod -eq "OPTIONS") {
            $context.Response.Headers.Add("Access-Control-Allow-Origin", "*")
            $context.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
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
    Stop-LocTaskRunner
    try {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
    catch { }
    Write-LocLog -Module "CORE" -Action "Server" -Level "INFO" -Message "Server stopped"
    if ($script:LocShutdownRequested) {
        [Environment]::Exit(0)
    }
}
