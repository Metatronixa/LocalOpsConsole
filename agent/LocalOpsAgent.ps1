#Requires -Version 5.1
# LocalOpsAgent.ps1 - Outbound fleet agent (v2.0.0)

$ErrorActionPreference = "Continue"
$AgentVersion = "2.0.0"
$ConfigDir = "C:\ProgramData\LocalOpsAgent"
$ConfigPath = Join-Path $ConfigDir "config.json"
$LogDir = Join-Path $ConfigDir "logs"
$HeartbeatIntervalSec = 30
$PollIntervalSec = 3

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
        return $null
    }
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
        [switch]$Signed
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

    $headers = @{ "Content-Type" = "application/json" }
    if ($Signed) {
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
        $sigPayload = "$ts$($Method.ToUpperInvariant())$Path$bodyText"
        $sig = Get-LocHmacHex -Secret ([string]$cfg.AgentSecret) -Message $sigPayload
        $headers["X-Loc-Agent"] = [string]$cfg.AgentId
        $headers["X-Loc-Timestamp"] = $ts
        $headers["X-Loc-Signature"] = $sig
    }

    $params = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $headers
        TimeoutSec  = 15
        UseBasicParsing = $true
    }
    if ($bodyText) { $params.Body = $bodyText }

    return Invoke-RestMethod @params
}

function Invoke-AgentEnroll {
    param([string]$ServerUrl, [string]$EnrollToken)

    $body = @{
        Token        = $EnrollToken
        ComputerName = $env:COMPUTERNAME
        AgentVersion = $AgentVersion
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

function Get-AgentTelemetry {
    $cpu = $null
    try {
        $c = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c -and $c.LoadPercentage -ne $null) { $cpu = [double]$c.LoadPercentage }
    }
    catch { }

    $ramPct = $null
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $total = [double]$os.TotalVisibleMemorySize
            $free = [double]$os.FreePhysicalMemory
            if ($total -gt 0) { $ramPct = [math]::Round((($total - $free) / $total) * 100, 1) }
        }
    }
    catch { }

    $diskFreePct = $null
    try {
        $sys = $env:SystemDrive
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sys'" -ErrorAction SilentlyContinue
        if ($d -and $d.Size -gt 0) {
            $diskFreePct = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
        }
    }
    catch { }

    $ipv4 = $null
    $gateway = $null
    try {
        $cfg = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } | Select-Object -First 1
        if ($cfg) {
            $ipv4 = ($cfg.IPv4Address | Select-Object -First 1).IPAddress
            $gateway = $cfg.IPv4DefaultGateway.NextHop
        }
    }
    catch { }

    $winVer = $null
    $uptimeSec = $null
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $winVer = "$($os.Caption) $($os.Version)"
            $uptimeSec = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds
        }
    }
    catch { }

    $internetOk = $null
    try {
        $internetOk = (Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }
    catch { }

    return @{
        ComputerName  = $env:COMPUTERNAME
        UserName      = "$env:USERDOMAIN\$env:USERNAME"
        CpuPct        = $cpu
        RamPct        = $ramPct
        DiskFreePct   = $diskFreePct
        IPv4          = $ipv4
        Gateway       = $gateway
        WindowsVersion = $winVer
        UptimeSec     = $uptimeSec
        InternetOk    = $internetOk
        AgentVersion  = $AgentVersion
    }
}

function Send-AgentHeartbeat {
    try {
        $tel = Get-AgentTelemetry
        $resp = Invoke-AgentApi -Method POST -Path "/api/v1/fleet/heartbeat" -Body $tel -Signed
        if (-not $resp.Success) {
            Write-AgentLog "Heartbeat rejected: $($resp.Message)" "WARN"
        }
    }
    catch {
        Write-AgentLog "Heartbeat error: $($_.Exception.Message)" "WARN"
    }
}

function Get-AgentPendingCommands {
    try {
        $resp = Invoke-AgentApi -Method GET -Path "/api/v1/fleet/poll" -Signed
        if ($resp.Success -and $resp.Data) {
            return @($resp.Data)
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

    $body = @{
        CommandId  = $CommandId
        Success    = $Success
        Message    = $Message
        Data       = $Data
        ExitCode   = $ExitCode
        DurationMs = $DurationMs
        LogLines   = @($LogLines)
    }
    try {
        Invoke-AgentApi -Method POST -Path "/api/v1/fleet/results" -Body $body -Signed | Out-Null
    }
    catch {
        Write-AgentLog "Result post failed: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-AgentCommand {
    param(
        [Parameter(Mandatory)] [string]$CommandId,
        [Parameter(Mandatory)] [string]$Type,
        [object]$Payload
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $logs = [System.Collections.ArrayList]::new()
    $success = $false
    $message = ""
    $data = $null
    $exitCode = 0

    function Add-Log([string]$Line) {
        [void]$logs.Add($Line)
        Write-AgentLog $Line
    }

    try {
        Add-Log "Executing $Type ($CommandId)"

        switch ($Type) {
            "RestartSpooler" {
                Restart-Service -Name Spooler -Force -ErrorAction Stop
                $message = "Print Spooler restarted"
                $success = $true
            }
            "FlushDns" {
                ipconfig /flushdns | Out-Null
                Clear-DnsClientCache -ErrorAction SilentlyContinue
                $message = "DNS cache flushed"
                $success = $true
            }
            "RestartService" {
                $svc = if ($Payload -and $Payload.ServiceName) { [string]$Payload.ServiceName } else { throw "ServiceName required" }
                Restart-Service -Name $svc -Force -ErrorAction Stop
                $message = "Service $svc restarted"
                $success = $true
            }
            "RunScript" {
                $scriptId = if ($Payload -and $Payload.ScriptId) { [string]$Payload.ScriptId } else { throw "ScriptId required" }
                $path = "/api/v1/fleet/scripts/$scriptId/content"
                $resp = Invoke-AgentApi -Method GET -Path $path -Signed
                if (-not $resp.Success) { throw $resp.Message }
                $content = [string]$resp.Data.Content
                $tmp = Join-Path $env:TEMP "loc-agent-$scriptId.ps1"
                Set-Content -Path $tmp -Value $content -Encoding UTF8
                $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1
                foreach ($line in @($out)) { Add-Log ([string]$line) }
                $message = "Script $scriptId executed"
                $success = ($LASTEXITCODE -eq 0)
                $exitCode = $LASTEXITCODE
            }
            "Message" {
                $text = if ($Payload -and $Payload.Text) { [string]$Payload.Text } else { "Message from LocalOpsConsole" }
                $title = if ($Payload -and $Payload.Title) { [string]$Payload.Title } else { "LocalOpsConsole" }
                try {
                    msg.exe * /TIME:60 "$title`: $text" 2>&1 | Out-Null
                    $message = "Message displayed"
                    $success = $true
                }
                catch {
                    Write-EventLog -LogName Application -Source "LocalOpsAgent" -EventId 1000 -EntryType Information -Message $text -ErrorAction SilentlyContinue
                    $message = "Message logged to event log (msg.exe unavailable)"
                    $success = $true
                }
            }
            "CollectInventory" {
                $software = @()
                try {
                    $software = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
                        HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName } |
                        Select-Object DisplayName, DisplayVersion, Publisher |
                        Sort-Object DisplayName |
                        Select-Object -First 50
                }
                catch { Add-Log "Software inventory partial: $($_.Exception.Message)" }

                $printers = @()
                try { $printers = @(Get-Printer -ErrorAction SilentlyContinue | Select-Object Name, DriverName, PortName) }
                catch { }

                $serial = $null
                $cpuName = $null
                $ramGb = $null
                try {
                    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
                    if ($bios) { $serial = $bios.SerialNumber }
                    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($cpu) { $cpuName = $cpu.Name }
                    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
                    if ($cs) { $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) }
                }
                catch { }

                $data = @{
                    Software = @($software)
                    Printers = @($printers)
                    BiosSerial = $serial
                    CpuName    = $cpuName
                    RamGB      = $ramGb
                    CollectedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                $message = "Inventory collected"
                $success = $true
            }
            "RestartComputer" {
                $delay = 60
                if ($Payload -and $Payload.DelaySec) { $delay = [int]$Payload.DelaySec }
                shutdown.exe /r /t $delay /c "LocalOpsConsole scheduled restart"
                $message = "Restart scheduled in ${delay}s"
                $success = $true
            }
            "GetServices" {
                $data = @(Get-Service -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType, DisplayName)
                $message = "Services listed"
                $success = $true
            }
            "GetProcesses" {
                $data = @(Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 50 Name, Id, CPU, WorkingSet64)
                $message = "Top processes listed"
                $success = $true
            }
            default {
                throw "Unknown command type: $Type"
            }
        }
    }
    catch {
        $message = $_.Exception.Message
        Add-Log "ERROR: $message"
        $success = $false
        if ($exitCode -eq 0) { $exitCode = 1 }
    }

    $sw.Stop()
    Send-AgentResult -CommandId $CommandId -Success $success -Message $message -Data $data -ExitCode $exitCode -DurationMs ([int]$sw.ElapsedMilliseconds) -LogLines @($logs)
}

# --- Main ---
Write-AgentLog "LocalOps Agent $AgentVersion starting"

$script:AgentConfig = Get-AgentConfig
if (-not $script:AgentConfig -or -not $script:AgentConfig.AgentId) {
    $enrollToken = $env:LOCALOPS_ENROLL_TOKEN
    $serverUrl = $env:LOCALOPS_SERVER_URL
    if (-not $enrollToken -and $script:AgentConfig -and $script:AgentConfig.EnrollToken) {
        $enrollToken = [string]$script:AgentConfig.EnrollToken
    }
    if (-not $serverUrl -and $script:AgentConfig -and $script:AgentConfig.ServerUrl) {
        $serverUrl = [string]$script:AgentConfig.ServerUrl
    }
    if (-not $enrollToken -or -not $serverUrl) {
        Write-AgentLog "No AgentId and missing EnrollToken/ServerUrl - exiting" "ERROR"
        exit 1
    }
    try {
        Invoke-AgentEnroll -ServerUrl $serverUrl -EnrollToken $enrollToken
    }
    catch {
        Write-AgentLog "Enrollment failed: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

$lastHeartbeat = [datetime]::MinValue

while ($true) {
    $now = Get-Date
    if (($now - $lastHeartbeat).TotalSeconds -ge $HeartbeatIntervalSec) {
        Send-AgentHeartbeat
        $lastHeartbeat = $now
    }

    $cmds = Get-AgentPendingCommands
    foreach ($cmd in $cmds) {
        $cid = if ($cmd.Id) { [string]$cmd.Id } else { [string]$cmd.id }
        $ctype = if ($cmd.Type) { [string]$cmd.Type } else { [string]$cmd.type }
        Invoke-AgentCommand -CommandId $cid -Type $ctype -Payload $cmd.Payload
    }

    Start-Sleep -Seconds $PollIntervalSec
}
