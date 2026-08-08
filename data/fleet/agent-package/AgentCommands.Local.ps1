# AgentCommands.Local.ps1 - Local inventory / soft-repair handlers
if (-not $script:LocAgentHandlers) { $script:LocAgentHandlers = @{} }

$script:LocAgentHandlers['GetPrinters'] = {
    param($r)
    $printers = @()
    try {
        $printers = @(Get-Printer -ErrorAction Stop | Select-Object Name, DriverName, PortName, PrinterStatus, Shared, Type)
    }
    catch {
        & $r.AddLog "Get-Printer failed: $($_.Exception.Message)"
    }
    $r.Data = @{ Printers = @($printers); Count = @($printers).Count }
    $r.Message = "Found $(@($printers).Count) printer(s)"
    $r.Success = $true
}

$script:LocAgentHandlers['GetStartupApps'] = {
    param($r)
    $items = @()
    $runKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($key in $runKeys) {
        if (-not (Test-Path $key)) { continue }
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) { continue }
            $items += [PSCustomObject]@{
                Name     = $p.Name
                Command  = [string]$p.Value
                Location = $key
                Source   = "Registry"
                Enabled  = $true
            }
        }
    }
    $startupFolder = [Environment]::GetFolderPath("Startup")
    if (Test-Path $startupFolder) {
        Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | ForEach-Object {
            $items += [PSCustomObject]@{
                Name     = $_.Name
                Command  = $_.FullName
                Location = $startupFolder
                Source   = "StartupFolder"
                Enabled  = $true
            }
        }
    }
    $r.Data = @($items)
    $r.Message = ("{0} startup item(s)" -f $items.Count)
    $r.Success = $true
}

$script:LocAgentHandlers['GetScheduledTasks'] = {
    param($r)
    $search = ""
    if ($r.Payload -and $r.Payload.Search) { $search = [string]$r.Payload.Search }
    $tasks = @(Get-ScheduledTask -ErrorAction Stop)
    if ($search) {
        $tasks = @($tasks | Where-Object { $_.TaskName -like "*$search*" -or $_.TaskPath -like "*$search*" })
    }
    $r.Data = @($tasks | Select-Object -First 100 | ForEach-Object {
            [PSCustomObject]@{
                TaskName = $_.TaskName
                TaskPath = $_.TaskPath
                State    = [string]$_.State
                Author   = $_.Author
            }
        })
    $r.Message = ("{0} task(s)" -f $r.Data.Count)
    $r.Success = $true
}

$script:LocAgentHandlers['DiskCleanup'] = {
    param($r)
    $temp = $env:TEMP
    $removed = 0
    Get-ChildItem -Path $temp -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Select-Object -First 200 |
        ForEach-Object {
            try { Remove-Item $_.FullName -Force -ErrorAction Stop; $removed++ } catch { }
        }
    $r.Data = @{ Removed = $removed }
    $r.Message = "Removed $removed old temp file(s)"
    $r.Success = $true
}

$script:LocAgentHandlers['ClearPrintQueue'] = {
    param($r)
    $removed = 0
    $printers = @(Get-Printer -ErrorAction SilentlyContinue)
    foreach ($p in $printers) {
        $jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue)
        foreach ($j in $jobs) {
            try {
                Remove-PrintJob -PrinterName $j.PrinterName -ID $j.Id -ErrorAction Stop
                $removed++
            }
            catch { }
        }
    }
    $r.Data = @{ Removed = $removed; PrinterCount = $printers.Count }
    $r.Message = "Cleared $removed print job(s) across $($printers.Count) printer(s)"
    $r.Success = $true
}

$script:LocAgentHandlers['NetworkSoftRepair'] = {
    param($r)
    $steps = @()
    try {
        Clear-DnsClientCache -ErrorAction Stop
        $steps += "Clear-DnsClientCache"
    }
    catch {
        $null = ipconfig /flushdns 2>&1
        $steps += "ipconfig /flushdns"
    }
    $null = ipconfig /flushdns 2>&1
    if ($steps -notcontains "ipconfig /flushdns") { $steps += "ipconfig /flushdns" }
    $null = ipconfig /release 2>&1
    $steps += "ipconfig /release"
    Start-Sleep -Seconds 1
    $null = ipconfig /renew 2>&1
    $steps += "ipconfig /renew"
    $r.Data = @{ Steps = @($steps) }
    $r.Message = ("Network soft repair: {0}" -f ($steps -join " -> "))
    $r.Success = $true
}

$script:LocAgentHandlers['RestartUpdateStack'] = {
    param($r)
    $names = @("wuauserv", "bits")
    $ok = @(); $fail = @()
    foreach ($svcName in $names) {
        try {
            Restart-Service -Name $svcName -Force -ErrorAction Stop
            Start-Sleep -Seconds 1
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -eq "Running") { $ok += $svcName }
            else { $fail += "$svcName=$($svc.Status)" }
        }
        catch { $fail += "$svcName=$($_.Exception.Message)" }
    }
    $r.Data = @{ Ok = @($ok); Failed = @($fail) }
    if ($fail.Count -eq 0) {
        $r.Message = ("Restarted update stack: {0}" -f ($ok -join ", "))
        $r.Success = $true
    }
    else {
        $r.Message = ("Update stack restart issues. OK: {0}; Failed: {1}" -f ($ok -join ", "), ($fail -join "; "))
        $r.Success = ($ok.Count -gt 0)
    }
}

$script:LocAgentHandlers['CaptureProcessSnapshot'] = {
    param($r)
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
        Sort-Object -Property @{ Expression = 'CPU'; Descending = $true }, @{ Expression = 'WorkingSet64'; Descending = $true } |
        Select-Object -First 15)
    $rows = foreach ($p in $procs) {
        [PSCustomObject]@{
            Name         = $p.ProcessName
            Id           = $p.Id
            CpuSeconds   = if ($null -eq $p.CPU) { 0 } else { [math]::Round([double]$p.CPU, 1) }
            WorkingSetMB = [math]::Round(($p.WorkingSet64 / 1MB), 1)
        }
    }
    $r.Data = @($rows)
    $r.Message = ("{0} process(es) captured" -f $rows.Count)
    $r.Success = $true
}
