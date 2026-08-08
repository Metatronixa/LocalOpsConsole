# AgentCommands.Core.ps1 - Core command handlers
if (-not $script:LocAgentHandlers) { $script:LocAgentHandlers = @{} }

$script:LocAgentHandlers['RestartSpooler'] = {
    param($r)
    Restart-Service -Name Spooler -Force -ErrorAction Stop
    $r.Message = "Print Spooler restarted"
    $r.Success = $true
}

$script:LocAgentHandlers['FlushDns'] = {
    param($r)
    ipconfig /flushdns | Out-Null
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    $r.Message = "DNS cache flushed"
    $r.Success = $true
}

$script:LocAgentHandlers['RestartService'] = {
    param($r)
    $svc = if ($r.Payload -and $r.Payload.ServiceName) { [string]$r.Payload.ServiceName } else { throw "ServiceName required" }
    Restart-Service -Name $svc -Force -ErrorAction Stop
    $r.Message = "Service $svc restarted"
    $r.Success = $true
}

$script:LocAgentHandlers['RunScript'] = {
    param($r)
    $scriptId = if ($r.Payload -and $r.Payload.ScriptId) { [string]$r.Payload.ScriptId } else { throw "ScriptId required" }
    $path = "/api/v1/fleet/scripts/$scriptId/content"
    $resp = Invoke-AgentApi -Method GET -Path $path -Signed -TimeoutSec 30
    if (-not $resp.Success) { throw $resp.Message }
    $content = [string]$resp.Data.Content
    $tmp = Join-Path $env:TEMP "loc-agent-$scriptId.ps1"
    Set-Content -Path $tmp -Value $content -Encoding UTF8
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1
    foreach ($line in @($out)) { & $r.AddLog ([string]$line) }
    $r.Message = "Script $scriptId executed"
    $r.Success = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    $r.ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
}

$script:LocAgentHandlers['Message'] = {
    param($r)
    $text = if ($r.Payload -and $r.Payload.Text) { [string]$r.Payload.Text } else { "Message from LocalOpsConsole" }
    $title = if ($r.Payload -and $r.Payload.Title) { [string]$r.Payload.Title } else { "LocalOpsConsole" }
    try {
        msg.exe * /TIME:60 "$title`: $text" 2>&1 | Out-Null
        $r.Message = "Message displayed"
        $r.Success = $true
    }
    catch {
        Write-EventLog -LogName Application -Source "LocalOpsAgent" -EventId 1000 -EntryType Information -Message $text -ErrorAction SilentlyContinue
        $r.Message = "Message logged to event log (msg.exe unavailable)"
        $r.Success = $true
    }
}

$script:LocAgentHandlers['CollectInventory'] = {
    param($r)
    $software = @()
    try {
        $software = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,
            HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher |
            Sort-Object DisplayName |
            Select-Object -First 50
    }
    catch { & $r.AddLog "Software inventory partial: $($_.Exception.Message)" }
    
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
    
    $r.Data = @{
        Software    = @($software)
        Printers    = @($printers)
        BiosSerial  = $serial
        CpuName     = $cpuName
        RamGB       = $ramGb
        CollectedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $r.Message = "Inventory collected"
    $r.Success = $true
}

$script:LocAgentHandlers['RestartComputer'] = {
    param($r)
    $delay = 60
    if ($r.Payload -and $r.Payload.DelaySec) { $delay = [int]$r.Payload.DelaySec }
    shutdown.exe /r /t $delay /c "LocalOpsConsole scheduled restart"
    $r.Message = "Restart scheduled in ${delay}s"
    $r.Success = $true
}

$script:LocAgentHandlers['GetServices'] = {
    param($r)
    $r.Data = @(Get-Service -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType, DisplayName)
    $r.Message = "Services listed"
    $r.Success = $true
}

$script:LocAgentHandlers['GetProcesses'] = {
    param($r)
    $r.Data = @(Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 60 Name, Id, CPU, @{n = 'WorkingSetMB'; e = { [math]::Round($_.WorkingSet64 / 1MB, 1) } })
    $r.Message = "Top processes listed"
    $r.Success = $true
}

$script:LocAgentHandlers['EndProcess'] = {
    param($r)
    $pidVal = $null
    if ($r.Payload -and $r.Payload.ProcessId) { $pidVal = [int]$r.Payload.ProcessId }
    if (-not $pidVal) { throw "ProcessId required" }
    $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
    if (-not $proc) { throw "Process $pidVal not found" }
    $name = [string]$proc.Name
    $protected = @('System', 'Idle', 'csrss', 'smss', 'wininit', 'services', 'lsass', 'Registry', 'Memory Compression')
    if ($protected -contains $name) { throw "Refusing to end protected process: $name ($pidVal)" }
    if ($r.Payload -and $r.Payload.ProcessName) {
        $expect = [string]$r.Payload.ProcessName
        if ($name -ne $expect -and ($name + '.exe') -ne $expect) {
            throw "Process name mismatch: running '$name' vs expected '$expect'"
        }
    }
    Stop-Process -Id $pidVal -Force -ErrorAction Stop
    $r.Message = "Ended process $name ($pidVal)"
    $r.Data = @{ ProcessId = $pidVal; ProcessName = $name }
    $r.Success = $true
}
