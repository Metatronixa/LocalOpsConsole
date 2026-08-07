#Requires -Version 5.1
# LocalOpsAgent.ps1 - Outbound fleet agent (v2.3.0)

$ErrorActionPreference = "Continue"
$AgentVersion = "2.3.0"
$ConfigDir = "C:\ProgramData\LocalOpsAgent"
$ConfigPath = Join-Path $ConfigDir "config.json"
$LogDir = Join-Path $ConfigDir "logs"
$HeartbeatIntervalSec = 30
$PollIntervalSec = 3
$script:AgentRestartAfterCommand = $false

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

function Get-AgentDiskIoMBps {
    $read = $null
    $write = $null
    # Prefer CIM formatted counters (no 1s Get-Counter sample that stalls the poll loop).
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        if ($perf) {
            $read = [math]::Round(([double]$perf.DiskReadBytesPerSec) / 1MB, 2)
            $write = [math]::Round(([double]$perf.DiskWriteBytesPerSec) / 1MB, 2)
        }
    }
    catch { }
    return @{ Read = $read; Write = $write }
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

    $io = Get-AgentDiskIoMBps

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
        # Soft timeout — Test-Connection can hang and starve the poll loop.
        $job = Start-Job -ScriptBlock {
            Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
        }
        if (Wait-Job $job -Timeout 3) {
            $internetOk = [bool](Receive-Job $job)
        }
        else {
            Stop-Job $job -ErrorAction SilentlyContinue
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
    catch { }

    return @{
        ComputerName   = $env:COMPUTERNAME
        UserName       = "$env:USERDOMAIN\$env:USERNAME"
        CpuPct         = $cpu
        RamPct         = $ramPct
        DiskFreePct    = $diskFreePct
        DiskReadMBps   = $io.Read
        DiskWriteMBps  = $io.Write
        IPv4           = $ipv4
        Gateway        = $gateway
        WindowsVersion = $winVer
        UptimeSec      = $uptimeSec
        InternetOk     = $internetOk
        AgentVersion   = $AgentVersion
    }
}

function Send-AgentHeartbeat {
    try {
        $tel = Get-AgentTelemetry
        $resp = Invoke-AgentApi -Method POST -Path "/api/v1/fleet/heartbeat" -Body $tel -Signed -TimeoutSec 20
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
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
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
                $resp = Invoke-AgentApi -Method GET -Path $path -Signed -TimeoutSec 30
                if (-not $resp.Success) { throw $resp.Message }
                $content = [string]$resp.Data.Content
                $tmp = Join-Path $env:TEMP "loc-agent-$scriptId.ps1"
                Set-Content -Path $tmp -Value $content -Encoding UTF8
                $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1
                foreach ($line in @($out)) { Add-Log ([string]$line) }
                $message = "Script $scriptId executed"
                $success = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
                $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
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
                try { $printers = @(Get-Printer -ErrorAction SilentlyContinue | Select-Object Name, DriverName, PortName, PrinterStatus) }
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
                    Software    = @($software)
                    Printers    = @($printers)
                    BiosSerial  = $serial
                    CpuName     = $cpuName
                    RamGB       = $ramGb
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
                $data = @(Get-Process -ErrorAction SilentlyContinue |
                    Sort-Object WorkingSet64 -Descending |
                    Select-Object -First 60 Name, Id, CPU, @{n = 'WorkingSetMB'; e = { [math]::Round($_.WorkingSet64 / 1MB, 1) } })
                $message = "Top processes listed"
                $success = $true
            }
            "EndProcess" {
                $pidVal = $null
                if ($Payload -and $Payload.ProcessId) { $pidVal = [int]$Payload.ProcessId }
                if (-not $pidVal) { throw "ProcessId required" }
                $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
                if (-not $proc) { throw "Process $pidVal not found" }
                $name = [string]$proc.Name
                $protected = @('System', 'Idle', 'csrss', 'smss', 'wininit', 'services', 'lsass', 'Registry', 'Memory Compression')
                if ($protected -contains $name) { throw "Refusing to end protected process: $name ($pidVal)" }
                if ($Payload -and $Payload.ProcessName) {
                    $expect = [string]$Payload.ProcessName
                    if ($name -ne $expect -and ($name + '.exe') -ne $expect) {
                        throw "Process name mismatch: running '$name' vs expected '$expect'"
                    }
                }
                Stop-Process -Id $pidVal -Force -ErrorAction Stop
                $message = "Ended process $name ($pidVal)"
                $data = @{ ProcessId = $pidVal; ProcessName = $name }
                $success = $true
            }
            "GetPrinters" {
                $printers = @()
                try {
                    $printers = @(Get-Printer -ErrorAction Stop | Select-Object Name, DriverName, PortName, PrinterStatus, Shared, Type)
                }
                catch {
                    Add-Log "Get-Printer failed: $($_.Exception.Message)"
                }
                $data = @{ Printers = @($printers); Count = @($printers).Count }
                $message = "Found $(@($printers).Count) printer(s)"
                $success = $true
            }
            "NetHealthSmoke" {
                $latencyMs = $null
                $pingOk = $false
                try {
                    $pings = Test-Connection -ComputerName 1.1.1.1 -Count 3 -ErrorAction Stop
                    $samples = @()
                    foreach ($p in @($pings)) {
                        if ($null -ne $p.ResponseTime) { $samples += [double]$p.ResponseTime }
                        elseif ($null -ne $p.Latency) { $samples += [double]$p.Latency }
                    }
                    if ($samples.Count -gt 0) {
                        $latencyMs = [math]::Round((($samples | Measure-Object -Average).Average), 1)
                        $pingOk = $true
                    }
                }
                catch {
                    Add-Log "Ping failed: $($_.Exception.Message)"
                }

                $downloadMbps = $null
                $downloadMs = $null
                $downloadOk = $false
                try {
                    $bytes = 200000
                    $url = "https://speed.cloudflare.com/__down?bytes=$bytes"
                    $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
                    $wc = New-Object System.Net.WebClient
                    try {
                        $null = $wc.DownloadData($url)
                    }
                    finally { $wc.Dispose() }
                    $dlSw.Stop()
                    $downloadMs = [int]$dlSw.ElapsedMilliseconds
                    if ($downloadMs -gt 0) {
                        $downloadMbps = [math]::Round((($bytes * 8.0) / ($downloadMs / 1000.0)) / 1000000.0, 2)
                        $downloadOk = $true
                    }
                }
                catch {
                    Add-Log "Download smoke failed: $($_.Exception.Message)"
                }

                $uploadMbps = $null
                $uploadMs = $null
                $uploadOk = $false
                try {
                    $upBytes = 100000
                    $payload = New-Object byte[] $upBytes
                    (New-Object System.Random).NextBytes($payload)
                    $upUrl = "https://speed.cloudflare.com/__up"
                    $upSw = [System.Diagnostics.Stopwatch]::StartNew()
                    $wcUp = New-Object System.Net.WebClient
                    try {
                        $null = $wcUp.UploadData($upUrl, 'POST', $payload)
                    }
                    finally { $wcUp.Dispose() }
                    $upSw.Stop()
                    $uploadMs = [int]$upSw.ElapsedMilliseconds
                    if ($uploadMs -gt 0) {
                        $uploadMbps = [math]::Round((($upBytes * 8.0) / ($uploadMs / 1000.0)) / 1000000.0, 2)
                        $uploadOk = $true
                    }
                }
                catch {
                    Add-Log "Upload smoke failed: $($_.Exception.Message)"
                }

                $data = @{
                    InternetLatencyMs = $latencyMs
                    PingOk            = $pingOk
                    DownloadMbps      = $downloadMbps
                    DownloadMs        = $downloadMs
                    DownloadOk        = $downloadOk
                    UploadMbps        = $uploadMbps
                    UploadMs          = $uploadMs
                    UploadOk          = $uploadOk
                    ProbedAt          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                $dlTxt = if ($downloadOk) { "$downloadMbps Mbps" } else { 'fail' }
                $upTxt = if ($uploadOk) { "$uploadMbps Mbps" } else { 'fail' }
                $pingTxt = if ($pingOk) { "${latencyMs}ms" } else { 'fail' }
                $message = "Net smoke: ping=$pingTxt dl=$dlTxt up=$upTxt"
                $success = ($pingOk -or $downloadOk -or $uploadOk)
            }
            "GetWindowsUpdateStatus" {
                $pendingReboot = $false
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $pendingReboot = $true }
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $pendingReboot = $true }
                $pending = @()
                $lastSuccess = $null
                $comError = $null
                try {
                    $wuJob = Start-Job -ScriptBlock {
                        $out = @{ Pending = @(); LastHistoryDate = $null; Error = $null }
                        try {
                            $session = New-Object -ComObject Microsoft.Update.Session
                            $searcher = $session.CreateUpdateSearcher()
                            $historyCount = $searcher.GetTotalHistoryCount()
                            if ($historyCount -gt 0) {
                                $hist = $searcher.QueryHistory(0, 1)
                                if ($hist.Count -gt 0) { $out.LastHistoryDate = $hist.Item(0).Date.ToString("yyyy-MM-dd HH:mm:ss") }
                            }
                            $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
                            $list = @()
                            for ($i = 0; $i -lt $result.Updates.Count -and $i -lt 25; $i++) {
                                $u = $result.Updates.Item($i)
                                $list += @{ Title = [string]$u.Title; IsDownloaded = [bool]$u.IsDownloaded; SizeMB = [math]::Round($u.MaxDownloadSize / 1MB, 1) }
                            }
                            $out.Pending = $list
                        }
                        catch {
                            $out.Error = $_.Exception.Message
                        }
                        return $out
                    }
                    if (Wait-Job $wuJob -Timeout 90) {
                        $wuOut = Receive-Job $wuJob
                        $pending = @($wuOut.Pending)
                        $lastSuccess = $wuOut.LastHistoryDate
                        if ($wuOut.Error) {
                            $comError = [string]$wuOut.Error
                            Add-Log "WU search: $comError"
                        }
                    }
                    else {
                        Stop-Job $wuJob -ErrorAction SilentlyContinue
                        $comError = "WU search timed out after 90s"
                        Add-Log $comError
                    }
                    Remove-Job $wuJob -Force -ErrorAction SilentlyContinue
                }
                catch {
                    $comError = $_.Exception.Message
                    Add-Log "WU search: $comError"
                }
                $data = @{
                    PendingReboot   = $pendingReboot
                    LastHistoryDate = $lastSuccess
                    PendingUpdates  = @($pending)
                    PendingCount    = @($pending).Count
                    Note            = $comError
                }
                $message = "Pending updates: $(@($pending).Count)"
                $success = $true
            }
            "InstallWindowsUpdates" {
                Add-Log "Searching pending Windows Updates..."
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
                if ($result.Updates.Count -eq 0) {
                    $message = "No pending updates"
                    $data = @{ InstalledCount = 0 }
                    $success = $true
                }
                else {
                    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
                    $titles = @()
                    $max = [Math]::Min(15, $result.Updates.Count)
                    for ($i = 0; $i -lt $max; $i++) {
                        $u = $result.Updates.Item($i)
                        if ($u.EulaAccepted -eq $false) { $u.AcceptEula() }
                        [void]$toInstall.Add($u)
                        $titles += [string]$u.Title
                        Add-Log "Queued: $($u.Title)"
                    }
                    $downloader = $session.CreateUpdateDownloader()
                    $downloader.Updates = $toInstall
                    Add-Log ("Downloading {0} update(s)..." -f $toInstall.Count)
                    $dlResult = $downloader.Download()
                    Add-Log "Download result code: $($dlResult.ResultCode)"
                    $installer = $session.CreateUpdateInstaller()
                    $installer.Updates = $toInstall
                    Add-Log "Installing..."
                    $instResult = $installer.Install()
                    $exitCode = [int]$instResult.ResultCode
                    $reboot = [bool]$instResult.RebootRequired
                    $data = @{
                        InstalledCount = $toInstall.Count
                        Titles         = @($titles)
                        ResultCode     = $exitCode
                        RebootRequired = $reboot
                    }
                    $success = ($exitCode -eq 2 -or $exitCode -eq 3)
                    $message = "Installed $($toInstall.Count) update(s); result=$exitCode; reboot=$reboot"
                }
            }
            "GetRustDeskStatus" {
                $exe = $null
                foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'RustDesk'))) {
                    if (-not $root) { continue }
                    $cand = Join-Path $root 'rustdesk.exe'
                    if (Test-Path $cand) { $exe = $cand; break }
                }
                $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*RustDesk*' -or $_.DisplayName -like '*RustDesk*' } | Select-Object -First 1
                $proc = [bool](Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue)
                $id = $null
                if ($exe) {
                    foreach ($cfgPath in @(
                            (Join-Path $env:APPDATA 'RustDesk\config\RustDesk2.toml'),
                            (Join-Path $env:LOCALAPPDATA 'RustDesk\config\RustDesk2.toml')
                        )) {
                        if (-not (Test-Path $cfgPath)) { continue }
                        try {
                            $text = Get-Content $cfgPath -Raw -ErrorAction Stop
                            if ($text -match '(?m)^\s*id\s*=\s*[''"]?(\d{6,12})') { $id = $Matches[1]; break }
                        }
                        catch { }
                    }
                }
                $data = @{
                    Installed      = [bool]$exe
                    ExePath        = $exe
                    ProcessRunning = $proc
                    ServiceName    = if ($svc) { [string]$svc.Name } else { $null }
                    ServiceStatus  = if ($svc) { [string]$svc.Status } else { $null }
                    Id             = $id
                    Note           = 'Remote passwords are never collected.'
                }
                $message = if ($exe) { "RustDesk installed" } else { "RustDesk not detected" }
                $success = $true
            }
            "InstallRustDesk" {
                $url = if ($Payload -and $Payload.InstallerUrl) { [string]$Payload.InstallerUrl } else { throw "InstallerUrl required (set rustDeskInstallerUrl on console)" }
                if ($url -notmatch '^https://') { throw "InstallerUrl must be HTTPS" }
                $sha = if ($Payload -and $Payload.InstallerSha256) { [string]$Payload.InstallerSha256 } else { '' }
                $silent = if ($Payload -and $Payload.SilentArgs) { [string]$Payload.SilentArgs } else { '/S' }
                $ext = [System.IO.Path]::GetExtension(($url -split '\?')[0])
                if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.exe' }
                $work = Join-Path $ConfigDir "installs\rustdesk"
                if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
                try { Start-Process explorer.exe -ArgumentList $work -ErrorAction SilentlyContinue } catch { }
                $tmp = Join-Path $work ("RustDesk-install-{0}{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $ext)
                Add-Log "Downloading RustDesk installer..."
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
                if (-not [string]::IsNullOrWhiteSpace($sha)) {
                    $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($actual -ne $sha.ToLowerInvariant()) { throw "SHA-256 mismatch" }
                }
                $argList = @()
                if ($silent -match '\s') { $argList = $silent.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) }
                elseif ($silent) { $argList = @($silent) }
                Add-Log "Running silent install..."
                $proc = Start-Process -FilePath $tmp -ArgumentList $argList -Wait -PassThru -ErrorAction Stop
                $exitCode = [int]$proc.ExitCode
                $pf = ${env:ProgramFiles}
                $pf86 = ${env:ProgramFiles(x86)}
                $installed = (Test-Path (Join-Path $pf 'RustDesk\rustdesk.exe')) -or (Test-Path (Join-Path $pf86 'RustDesk\rustdesk.exe'))
                $data = @{ ExitCode = $exitCode; Installed = [bool]$installed; WorkDir = $work }
                $success = ($installed -or $exitCode -eq 0)
                $message = if ($installed) { "RustDesk installed" } else { "Installer finished (exit $exitCode) - verify status" }
            }
            "InstallPackage" {
                $pkgId = if ($Payload -and $Payload.PackageId) { [string]$Payload.PackageId } else { throw "PackageId required" }
                $name = if ($Payload -and $Payload.Name) { [string]$Payload.Name } else { $pkgId }
                $wingetId = if ($Payload -and $Payload.WingetId) { [string]$Payload.WingetId } else { '' }
                $url = if ($Payload -and $Payload.Url) { [string]$Payload.Url } else { '' }
                $silent = if ($Payload -and $Payload.SilentArgs) { [string]$Payload.SilentArgs } else { '' }
                $sha = if ($Payload -and $Payload.Sha256) { [string]$Payload.Sha256 } else { '' }
                $work = Join-Path $ConfigDir "installs\$pkgId"
                if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
                try { Start-Process explorer.exe -ArgumentList $work -ErrorAction SilentlyContinue } catch { }
                Add-Log "Install work dir: $work"
                $method = $null
                if ($wingetId) {
                    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
                    if ($winget) {
                        $method = 'winget'
                        Add-Log "winget install $wingetId"
                        $wg = Invoke-AgentCapturedProcess -FilePath $winget.Source -ArgumentList @(
                            'install', '--id', $wingetId, '-e', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
                        ) -TimeoutSec 900
                        foreach ($line in ($wg.StdOut -split "`r?`n")) { Add-Log $line }
                        foreach ($line in ($wg.StdErr -split "`r?`n")) { Add-Log $line }
                        $exitCode = [int]$wg.ExitCode
                        $success = ($exitCode -eq 0)
                        $message = "winget install $name exit $exitCode"
                        $data = @{ PackageId = $pkgId; Name = $name; Method = $method; ExitCode = $exitCode; WorkDir = $work }
                    }
                }
                if (-not $method) {
                    if ([string]::IsNullOrWhiteSpace($url)) { throw "No winget and no Url for package $pkgId" }
                    if ($url -notmatch '^https://') { throw "Package Url must be HTTPS" }
                    $method = 'url'
                    $ext = [System.IO.Path]::GetExtension(($url -split '\?')[0])
                    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.exe' }
                    $tmp = Join-Path $work ("install-{0}{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $ext)
                    Add-Log "Downloading $url"
                    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
                    if (-not [string]::IsNullOrWhiteSpace($sha)) {
                        $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
                        if ($actual -ne $sha.ToLowerInvariant()) { throw "SHA-256 mismatch" }
                    }
                    $argList = @()
                    if ($silent -match '\s') { $argList = $silent.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) }
                    elseif ($silent) { $argList = @($silent) }
                    $proc = Start-Process -FilePath $tmp -ArgumentList $argList -Wait -PassThru -ErrorAction Stop
                    $exitCode = [int]$proc.ExitCode
                    $success = ($exitCode -eq 0)
                    $message = "URL install $name exit $exitCode"
                    $data = @{ PackageId = $pkgId; Name = $name; Method = $method; ExitCode = $exitCode; WorkDir = $work }
                }
            }
            "GetEventLogTail" {
                $logName = 'System'
                if ($Payload -and $Payload.LogName) { $logName = [string]$Payload.LogName }
                $allowed = @('System', 'Application', 'Security')
                if ($allowed -notcontains $logName) { $logName = 'System' }
                $count = 40
                if ($Payload -and $Payload.Count) { $count = [Math]::Min(100, [Math]::Max(5, [int]$Payload.Count)) }
                $entries = @(Get-WinEvent -LogName $logName -MaxEvents $count -ErrorAction SilentlyContinue | ForEach-Object {
                        $msg = [string]$_.Message
                        if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
                        @{
                            TimeCreated = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                            Id          = $_.Id
                            Level       = [string]$_.LevelDisplayName
                            Provider    = [string]$_.ProviderName
                            Message     = $msg
                        }
                    })
                $data = @{ LogName = $logName; Count = $entries.Count; Entries = @($entries) }
                $message = ('Event log {0} ({1} entries)' -f $logName, $entries.Count)
                $success = $true
            }
            "GetResourceOffenders" {
                $topN = 8
                if ($Payload -and $Payload.Top) { $topN = [Math]::Min(20, [Math]::Max(3, [int]$Payload.Top)) }
                $procs = @(Get-Process -ErrorAction SilentlyContinue |
                    Sort-Object WorkingSet64 -Descending |
                    Select-Object -First $topN |
                    ForEach-Object {
                        $svcMatch = $null
                        try {
                            $svc = Get-CimInstance Win32_Service -Filter ("ProcessId={0}" -f $_.Id) -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($svc) { $svcMatch = @{ Name = [string]$svc.Name; DisplayName = [string]$svc.DisplayName; State = [string]$svc.State } }
                        }
                        catch { }
                        @{
                            Name           = [string]$_.Name
                            Id             = $_.Id
                            CPU            = $_.CPU
                            WorkingSetMB   = [math]::Round($_.WorkingSet64 / 1MB, 1)
                            RelatedService = $svcMatch
                        }
                    })
                $related = $null
                if ($procs.Count -gt 0 -and $procs[0].RelatedService) { $related = $procs[0].RelatedService }
                $summary = if ($procs.Count -gt 0) {
                    $svcBit = if ($related) { (' / {0}' -f $related.Name) } else { '' }
                    '{0} ({1} MB){2}' -f $procs[0].Name, $procs[0].WorkingSetMB, $svcBit
                } else { 'No processes' }
                $data = @{
                    TopProcesses   = @($procs)
                    RelatedService = $related
                    Summary        = $summary
                    CapturedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                $message = "Offenders: $summary"
                $success = $true
            }
            "SfcScannow" {
                Add-Log "Starting sfc /scannow (may take a long time)..."
                $sfc = Invoke-AgentCapturedProcess -FilePath "$env:SystemRoot\System32\sfc.exe" -ArgumentList @('/scannow')
                foreach ($line in ($sfc.StdOut -split "`r?`n")) { Add-Log $line }
                foreach ($line in ($sfc.StdErr -split "`r?`n")) { Add-Log $line }
                $exitCode = [int]$sfc.ExitCode
                $success = ($exitCode -eq 0)
                $message = "sfc /scannow finished (exit $exitCode)"
                $data = @{ ExitCode = $exitCode }
            }
            "SelfUpdate" {
                $force = $false
                if ($Payload -and $Payload.Force) { $force = [bool]$Payload.Force }

                Add-Log "Fetching agent package manifest..."
                $manResp = Invoke-AgentApi -Method GET -Path "/api/v1/fleet/agent-package/manifest" -Signed -TimeoutSec 30
                if (-not $manResp.Success) { throw ("Manifest failed: {0}" -f $manResp.Message) }
                $pkgVer = [string]$manResp.Data.Version
                $pkgSha = ([string]$manResp.Data.Sha256).ToLowerInvariant()
                Add-Log ("Package version {0} sha={1}" -f $pkgVer, $pkgSha)

                if (-not $force -and $pkgVer -eq $AgentVersion) {
                    $message = "Already on agent $AgentVersion"
                    $data = @{ Version = $AgentVersion; Updated = $false }
                    $success = $true
                }
                else {
                    Add-Log "Downloading agent package content..."
                    $contentResp = Invoke-AgentApi -Method GET -Path "/api/v1/fleet/agent-package/content" -Signed -TimeoutSec 120
                    if (-not $contentResp.Success) { throw ("Content failed: {0}" -f $contentResp.Message) }
                    $respSha = ([string]$contentResp.Data.Sha256).ToLowerInvariant()

                    $updatesDir = Join-Path $ConfigDir "updates"
                    if (-not (Test-Path $updatesDir)) { New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null }
                    $tmpFile = Join-Path $updatesDir ("LocalOpsAgent-{0}.ps1" -f $pkgVer)

                    if ($contentResp.Data.ContentBase64) {
                        $bytes = [Convert]::FromBase64String([string]$contentResp.Data.ContentBase64)
                        [System.IO.File]::WriteAllBytes($tmpFile, $bytes)
                    }
                    else {
                        $content = [string]$contentResp.Data.Content
                        if ([string]::IsNullOrWhiteSpace($content)) { throw "Empty agent package content" }
                        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                        [System.IO.File]::WriteAllText($tmpFile, $content, $utf8NoBom)
                    }

                    $actualSha = (Get-FileHash -Path $tmpFile -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($actualSha -ne $pkgSha -and $actualSha -ne $respSha) {
                        throw ("SHA-256 mismatch. expected={0} actual={1}" -f $pkgSha, $actualSha)
                    }

                    $installDir = "C:\Program Files\LocalOpsAgent"
                    if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir -Force | Out-Null }
                    $dest = Join-Path $installDir "LocalOpsAgent.ps1"
                    Copy-Item -Path $tmpFile -Destination $dest -Force
                    Add-Log "Replaced $dest"

                    $cfg = Get-AgentConfig
                    if (-not $cfg) { $cfg = [ordered]@{} }
                    if ($cfg -is [PSCustomObject]) {
                        $cfg | Add-Member -NotePropertyName AgentVersion -NotePropertyValue $pkgVer -Force
                    }
                    else {
                        $cfg.AgentVersion = $pkgVer
                    }
                    Save-AgentConfig -Config $cfg
                    $script:AgentConfig = $cfg

                    $message = "Updated agent to $pkgVer; restarting task"
                    $data = @{
                        PreviousVersion = $AgentVersion
                        Version         = $pkgVer
                        Sha256          = $actualSha
                        Updated         = $true
                        RestartPending  = $true
                    }
                    $success = $true
                    $script:AgentRestartAfterCommand = $true
                }
            }
            "ChkdskScan" {
                $drive = "C:"
                if ($Payload -and $Payload.Drive) { $drive = ([string]$Payload.Drive).TrimEnd('\') }
                if ($drive -notmatch '^[A-Za-z]:$') { $drive = "C:" }
                Add-Log "Running read-only chkdsk $drive..."
                $chk = Invoke-AgentCapturedProcess -FilePath "$env:SystemRoot\System32\chkdsk.exe" -ArgumentList @($drive) -TimeoutSec 600
                foreach ($line in ($chk.StdOut -split "`r?`n")) { Add-Log $line }
                foreach ($line in ($chk.StdErr -split "`r?`n")) { Add-Log $line }
                $exitCode = [int]$chk.ExitCode
                $success = ($exitCode -eq 0)
                $message = "chkdsk $drive finished (exit $exitCode)"
                $data = @{ Drive = $drive; ExitCode = $exitCode }
            }
            "ChkdskScheduleFix" {
                $drive = "C:"
                if ($Payload -and $Payload.Drive) { $drive = ([string]$Payload.Drive).TrimEnd('\') }
                if ($drive -notmatch '^[A-Za-z]:$') { $drive = "C:" }
                Add-Log "Scheduling chkdsk $drive /F (may require reboot; no auto-reboot)..."
                $psiArgs = "/c echo Y| chkdsk $drive /F"
                $chk = Invoke-AgentCapturedProcess -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @($psiArgs) -TimeoutSec 120
                foreach ($line in ($chk.StdOut -split "`r?`n")) { Add-Log $line }
                foreach ($line in ($chk.StdErr -split "`r?`n")) { Add-Log $line }
                $exitCode = [int]$chk.ExitCode
                $outAll = "$($chk.StdOut)`n$($chk.StdErr)"
                $scheduled = ($outAll -match '(?i)schedule|next time the system restarts|would you like to schedule')
                $success = ($exitCode -eq 0 -or $scheduled)
                $message = if ($scheduled) {
                    "CHKDSK /F scheduled for $drive on next restart (reboot not triggered)"
                } else {
                    "chkdsk $drive /F finished (exit $exitCode)"
                }
                $data = @{ Drive = $drive; ExitCode = $exitCode; Scheduled = [bool]$scheduled }
            }
            "AuditSecurityBaseline" {
                Add-Log "Auditing security baseline (compact)..."
                $checks = New-Object System.Collections.ArrayList
                $pass = 0; $fail = 0; $warn = 0; $unknown = 0
                function Add-AgentCheck([string]$Name, [string]$Status, [string]$Detail) {
                    [void]$checks.Add([PSCustomObject]@{ Name = $Name; Status = $Status; Detail = $Detail })
                    switch ($Status) {
                        'Pass' { $script:__acPass++ }
                        'Fail' { $script:__acFail++ }
                        'Warning' { $script:__acWarn++ }
                        default { $script:__acUnk++ }
                    }
                }
                $script:__acPass = 0; $script:__acFail = 0; $script:__acWarn = 0; $script:__acUnk = 0
                try {
                    $mp = Get-MpComputerStatus -ErrorAction Stop
                    if ([bool]$mp.RealTimeProtectionEnabled -and [bool]$mp.AntivirusEnabled) {
                        Add-AgentCheck 'Microsoft Defender' 'Pass' 'Realtime and antivirus enabled'
                    }
                    elseif ([bool]$mp.AntivirusEnabled) {
                        Add-AgentCheck 'Microsoft Defender' 'Warning' 'Antivirus on; realtime off'
                    }
                    else {
                        Add-AgentCheck 'Microsoft Defender' 'Fail' 'Defender not fully enabled'
                    }
                }
                catch { Add-AgentCheck 'Microsoft Defender' 'Unknown' $_.Exception.Message }
                try {
                    $profiles = Get-NetFirewallProfile -ErrorAction Stop
                    $disabled = @($profiles | Where-Object { -not $_.Enabled })
                    if ($disabled.Count -eq 0) {
                        Add-AgentCheck 'Windows Firewall' 'Pass' 'All profiles enabled'
                    }
                    else {
                        Add-AgentCheck 'Windows Firewall' 'Fail' ("Disabled: {0}" -f (($disabled | ForEach-Object Name) -join ', '))
                    }
                }
                catch { Add-AgentCheck 'Windows Firewall' 'Unknown' $_.Exception.Message }

                $total = $checks.Count
                $score = if ($total -gt 0) {
                    [int][math]::Round(100.0 * $script:__acPass / $total)
                } else { 0 }
                $success = $true
                $message = "Baseline audit score $score%"
                $data = @{
                    Score   = $score
                    Pass    = $script:__acPass
                    Fail    = $script:__acFail
                    Warning = $script:__acWarn
                    Unknown = $script:__acUnk
                    Checks  = @($checks)
                }
            }
            "ApplySecurityPolicy" {
                $packId = "hardening-basic"
                if ($Payload -and $Payload.PackId) { $packId = [string]$Payload.PackId }
                $allowedPacks = @('hardening-basic')
                if ($allowedPacks -notcontains $packId) { throw "Unknown or disallowed pack: $packId" }

                $controlIds = @('firewall-enable-all', 'defender-realtime-on')
                if ($Payload -and $Payload.ControlIds) {
                    $controlIds = @($Payload.ControlIds | ForEach-Object { [string]$_ })
                }

                $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)
                if (-not $isAdmin) { throw "ApplySecurityPolicy requires an elevated agent (Administrator)" }

                Add-Log "Applying policy pack $packId..."
                $results = New-Object System.Collections.ArrayList
                foreach ($cid in $controlIds) {
                    $ok = $false
                    $detail = ""
                    try {
                        switch ($cid) {
                            'firewall-enable-all' {
                                Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
                                $ok = $true
                                $detail = "Firewall Domain/Private/Public enabled"
                            }
                            'defender-realtime-on' {
                                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
                                $ok = $true
                                $detail = "Defender realtime monitoring enabled"
                            }
                            default {
                                $detail = "Unknown control id (skipped)"
                            }
                        }
                    }
                    catch {
                        $ok = $false
                        $detail = $_.Exception.Message
                    }
                    Add-Log ("{0}: {1} — {2}" -f $cid, $(if ($ok) { 'OK' } else { 'FAIL' }), $detail)
                    [void]$results.Add([PSCustomObject]@{ Id = $cid; Ok = $ok; Detail = $detail })
                }
                $failed = @($results | Where-Object { -not $_.Ok }).Count
                $success = ($failed -eq 0)
                $message = if ($success) { "Applied $packId ($($results.Count) controls)" } else { "Applied $packId with $failed failure(s)" }
                $data = @{
                    PackId  = $packId
                    Results = @($results)
                }
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

    if ($script:AgentRestartAfterCommand) {
        Write-AgentLog "SelfUpdate complete - restarting LocalOpsAgent scheduled task"
        try {
            $psExe = (Get-Command powershell.exe).Source
            $restartCmd = 'Start-Sleep -Seconds 3; Start-ScheduledTask -TaskName ''LocalOpsAgent'''
            Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', $restartCmd) -WindowStyle Hidden | Out-Null
        }
        catch {
            Write-AgentLog ("Failed to schedule restart: {0}" -f $_.Exception.Message) "ERROR"
        }
        exit 0
    }
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
