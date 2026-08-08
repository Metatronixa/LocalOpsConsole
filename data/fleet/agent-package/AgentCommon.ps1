# AgentCommon.ps1 - Logging, config, HMAC, HTTP, enroll/poll/results helpers

if (-not (Get-Command New-ApiResult -ErrorAction SilentlyContinue)) {
    function New-ApiResult {
        param(
            [bool]$Success = $true,
            [string]$Message = "",
            [object]$Data = $null,
            [int]$StatusCode = 200
        )
        if ($null -eq $Data) { $Data = @{} }
        return [PSCustomObject]@{
            Success    = $Success
            Message    = $Message
            Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Data       = $Data
            StatusCode = $StatusCode
        }
    }
}

function Write-AgentLog {
    param([string]$Message, [string]$Level = "INFO")
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $logFile = Join-Path $LogDir ("agent-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Get-AgentConfig {
    if (-not (Test-Path $ConfigPath)) { return $null }
    try {
        return (Get-Content $ConfigPath -Raw | ConvertFrom-Json)
    }
    catch {
        Write-AgentLog "Failed to read config: $($_.Exception.Message)" "ERROR"
    }
    return $null
}

function Save-AgentConfig {
    param([object]$Config)
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    ($Config | ConvertTo-Json -Depth 5) | Set-Content $ConfigPath -Encoding UTF8
}

function Get-LocHmacHex {
    param([string]$Secret, [string]$Message)
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
    $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $keyBytes
    try {
        $hash = $hmac.ComputeHash($msgBytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally { $hmac.Dispose() }
}

function Invoke-AgentApi {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [object]$Body = $null,
        [switch]$Signed,
        [int]$TimeoutSec = 30
    )

    $cfg = $script:AgentConfig
    if (-not $cfg -or -not $cfg.ServerUrl) {
        throw "Agent not configured"
    }

    $base = [string]$cfg.ServerUrl
    if ($base.EndsWith("/")) { $base = $base.TrimEnd("/") }
    $uri = "$base$Path"
    $bodyText = ""
    if ($null -ne $Body) {
        $bodyText = ($Body | ConvertTo-Json -Depth 8 -Compress)
    }

    $headers = @{}
    if ($bodyText) {
        $headers["Content-Type"] = "application/json"
    }
    if ($Signed) {
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
        $sigPayload = "$ts$($Method.ToUpperInvariant())$Path$bodyText"
        $sig = Get-LocHmacHex -Secret ([string]$cfg.AgentSecret) -Message $sigPayload
        $headers["X-Loc-Agent"] = [string]$cfg.AgentId
        $headers["X-Loc-Timestamp"] = $ts
        $headers["X-Loc-Signature"] = $sig
    }

    $params = @{
        Uri             = $uri
        Method          = $Method
        TimeoutSec      = $TimeoutSec
        UseBasicParsing = $true
    }
    if ($headers.Count -gt 0) { $params.Headers = $headers }
    if ($bodyText) {
        $params.Body = $bodyText
        $params.ContentType = "application/json"
    }

    return Invoke-RestMethod @params
}

function Invoke-AgentEnroll {
    param([string]$ServerUrl, [string]$EnrollToken)

    $caps = @()
    try { $caps = @(Get-LocAgentCapabilities) } catch { $caps = @() }

    $body = @{
        Token        = $EnrollToken
        ComputerName = $env:COMPUTERNAME
        AgentVersion = $AgentVersion
        Capabilities = @($caps)
    }
    $base = $ServerUrl.TrimEnd("/")
    $path = "/api/v1/fleet/enroll"
    $uri = "$base$path"
    $bodyText = $body | ConvertTo-Json -Compress

    $resp = Invoke-RestMethod -Uri $uri -Method POST -Body $bodyText -ContentType "application/json" -TimeoutSec 30
    if (-not $resp.Success) {
        throw "Enrollment failed: $($resp.Message)"
    }

    $cfg = [ordered]@{
        ServerUrl   = $base
        AgentId     = $resp.Data.AgentId
        AgentSecret = $resp.Data.AgentSecret
        EnrolledAt  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    Save-AgentConfig -Config $cfg
    $script:AgentConfig = $cfg
    Write-AgentLog "Enrolled as $($cfg.AgentId)"
}

function Get-AgentPendingCommands {
    try {
        $resp = Invoke-AgentApi -Method GET -Path "/api/v1/fleet/poll" -Signed -TimeoutSec 20
        if ($resp.Success -and $resp.Data) {
            return @($resp.Data)
        }
        if (-not $resp.Success) {
            Write-AgentLog "Poll rejected: $($resp.Message)" "WARN"
        }
    }
    catch {
        Write-AgentLog "Poll error: $($_.Exception.Message)" "WARN"
    }
    return @()
}

function Send-AgentResult {
    param(
        [string]$CommandId,
        [bool]$Success,
        [string]$Message,
        [object]$Data = $null,
        [int]$ExitCode = 0,
        [int]$DurationMs = 0,
        [object[]]$LogLines = @()
    )

    $lines = @($LogLines)
    if ($lines.Count -gt 200) {
        $lines = @($lines | Select-Object -Last 200)
    }

    $body = @{
        CommandId  = $CommandId
        Success    = $Success
        Message    = $Message
        Data       = $Data
        ExitCode   = $ExitCode
        DurationMs = $DurationMs
        LogLines   = $lines
    }
    try {
        Invoke-AgentApi -Method POST -Path "/api/v1/fleet/results" -Body $body -Signed -TimeoutSec 90 | Out-Null
    }
    catch {
        Write-AgentLog "Result post failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-AgentCapturedProcess {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSec = 0
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($ArgumentList -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    if ($TimeoutSec -gt 0) {
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch { }
            throw "Timed out after ${TimeoutSec}s: $FilePath"
        }
    }
    else {
        $p.WaitForExit()
    }
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}
