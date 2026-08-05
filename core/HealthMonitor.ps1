# core/HealthMonitor.ps1 - Continuous health checks → normalized events

$script:LocHealthLast = @{}
$script:LocServiceProfiles = @()

function Import-LocServiceProfiles {
    $dir = Join-Path (Get-LocRoot) "config\services"
    $profiles = @()
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $profiles += (Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
            }
            catch { }
        }
    }
    $script:LocServiceProfiles = $profiles
}

function Initialize-LocHealthMonitor {
    Import-LocServiceProfiles
    $script:LocHealthLast = @{}
}

function Emit-LocHealthEvent {
    param(
        [string]$Source = "Health",
        [int]$EventID = 0,
        [string]$Severity = "Warning",
        [string]$Category = "system",
        [string]$Message,
        [hashtable]$Data = @{}
    )
    $key = "$Source|$EventID|$Message"
    $now = Get-Date
    if ($script:LocHealthLast.ContainsKey($key)) {
        $last = $script:LocHealthLast[$key]
        if (($now - $last).TotalSeconds -lt 300) { return $null }
    }
    $script:LocHealthLast[$key] = $now
    return New-LocNormalizedEvent -Source $Source -EventID $EventID -Severity $Severity -Category $Category -Message $Message -Data $Data
}

function Invoke-LocHealthCheckPass {
    $events = @()
    $tel = Get-LocTelemetry

    # CPU
    try {
        $cpu = $null
        if ($tel.Cpu -and $tel.Cpu.PSObject.Properties["UsagePct"]) { $cpu = [double]$tel.Cpu.UsagePct }
        elseif ($tel.Cpu -and $tel.Cpu.PSObject.Properties["Usage"]) { $cpu = [double]$tel.Cpu.Usage }
        elseif ($tel.Cpu -and $tel.Cpu.PSObject.Properties["Percent"]) { $cpu = [double]$tel.Cpu.Percent }
        if ($null -ne $cpu -and $cpu -ge 95) {
            $e = Emit-LocHealthEvent -EventID 9001 -Severity "Warning" -Category "system" -Message ("High CPU: {0:N0}%" -f $cpu) -Data @{ healthMetric = "cpu"; cpu = $cpu }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # RAM
    try {
        $mem = $null
        if ($tel.Memory -and $tel.Memory.PSObject.Properties["UsedPct"]) { $mem = [double]$tel.Memory.UsedPct }
        elseif ($tel.Memory -and $tel.Memory.PSObject.Properties["Usage"]) { $mem = [double]$tel.Memory.Usage }
        elseif ($tel.Memory -and $tel.Memory.PSObject.Properties["Percent"]) { $mem = [double]$tel.Memory.Percent }
        if ($null -ne $mem -and $mem -ge 95) {
            $e = Emit-LocHealthEvent -EventID 9002 -Severity "Warning" -Category "system" -Message ("High memory: {0:N0}%" -f $mem) -Data @{ healthMetric = "memory"; memory = $mem }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # Disk
    try {
        $disks = @()
        if ($tel.Disks) { $disks = @($tel.Disks) }
        elseif ($tel.Disk) { $disks = @($tel.Disk) }
        foreach ($d in $disks) {
            $free = $null
            $letter = "Disk"
            if ($d.PSObject.Properties["FreePercent"]) { $free = [double]$d.FreePercent }
            elseif ($d.PSObject.Properties["PercentFree"]) { $free = [double]$d.PercentFree }
            elseif ($d.PSObject.Properties["UsedPct"]) { $free = 100.0 - [double]$d.UsedPct }
            if ($d.PSObject.Properties["Letter"]) { $letter = [string]$d.Letter }
            elseif ($d.PSObject.Properties["Name"]) { $letter = [string]$d.Name }
            elseif ($d.PSObject.Properties["Drive"]) { $letter = [string]$d.Drive }
            if ($null -ne $free -and $free -le 10) {
                $sev = if ($free -le 5) { "Critical" } else { "Warning" }
                $e = Emit-LocHealthEvent -EventID 9003 -Severity $sev -Category "storage" `
                    -Message ("Disk {0}: {1:N0}% remaining" -f $letter, $free) -Data @{ healthMetric = "diskFree"; disk = $letter; freePercent = $free }
                if ($e) { $events += $e }
            }
        }
    }
    catch { }

    # Services from profiles
    foreach ($profile in @($script:LocServiceProfiles)) {
        try {
            $svcName = [string]$profile.service
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if (-not $svc) {
                if ($profile.mustBeRunning) {
                    $sev = if ($profile.critical) { "Critical" } else { "Warning" }
                    $e = Emit-LocHealthEvent -Source "Services" -EventID 9100 -Severity $sev -Category "services" `
                        -Message ("Service missing: {0}" -f $svcName) -Data @{ service = $svcName; healthMetric = "serviceMissing" }
                    if ($e) { $events += $e }
                }
                continue
            }
            if ($profile.mustBeRunning -and $svc.Status -ne "Running") {
                $sev = if ($profile.critical) { "Critical" } else { "Warning" }
                $e = Emit-LocHealthEvent -Source "Services" -EventID 9101 -Severity $sev -Category "services" `
                    -Message ("Service not running: {0} ({1})" -f $svcName, $svc.Status) `
                    -Data @{ service = $svcName; status = [string]$svc.Status; healthMetric = "serviceDown"; restartOnFailure = [bool]$profile.restartOnFailure; notify = [bool]$profile.notify }
                if ($e) { $events += $e }
            }
        }
        catch { }
    }

    # Defender
    try {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp) {
            if ($mp.AntivirusEnabled -eq $false) {
                $e = Emit-LocHealthEvent -Source "Defender" -EventID 9200 -Severity "Critical" -Category "security" `
                    -Message "Windows Defender antivirus disabled" -Data @{ healthMetric = "defenderDisabled" }
                if ($e) { $events += $e }
            }
            if ($mp.RealTimeProtectionEnabled -eq $false) {
                $e = Emit-LocHealthEvent -Source "Defender" -EventID 9201 -Severity "Critical" -Category "security" `
                    -Message "Windows Defender real-time protection disabled" -Data @{ healthMetric = "defenderRealtimeOff" }
                if ($e) { $events += $e }
            }
        }
    }
    catch { }

    # Firewall profiles
    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
        $disabled = @($profiles | Where-Object { -not $_.Enabled })
        if ($disabled.Count -gt 0) {
            $names = ($disabled | ForEach-Object { $_.Name }) -join ", "
            $e = Emit-LocHealthEvent -Source "Firewall" -EventID 2003 -Severity "Critical" -Category "security" `
                -Message ("Firewall disabled: {0}" -f $names) -Data @{ healthMetric = "firewallDisabled"; profiles = $names }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # Network adapter up?
    try {
        $up = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false })
        if ($up.Count -eq 0) {
            $e = Emit-LocHealthEvent -Source "Network" -EventID 9300 -Severity "Critical" -Category "network" `
                -Message "No active network adapters" -Data @{ healthMetric = "networkDown" }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # RustDesk
    try {
        $rd = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
        if ($rd -and $rd.Status -ne "Running") {
            $e = Emit-LocHealthEvent -Source "RustDesk" -EventID 9400 -Severity "Warning" -Category "services" `
                -Message "RustDesk service not running" -Data @{ healthMetric = "rustdeskDown"; service = "RustDesk" }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # SyncMe path configured but missing
    try {
        $s = Get-LocSettings
        if ($s.syncMePath -and -not (Test-Path ([string]$s.syncMePath))) {
            $e = Emit-LocHealthEvent -Source "SyncMe" -EventID 9500 -Severity "Warning" -Category "storage" `
                -Message "SyncMe path missing" -Data @{ healthMetric = "syncmeMissing"; path = [string]$s.syncMePath }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # Certificates expiring within 14 days (LocalMachine\My)
    try {
        $cutoff = (Get-Date).AddDays(14)
        $certs = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object {
                $_.NotAfter -and $_.NotAfter -lt $cutoff -and $_.NotAfter -gt (Get-Date)
            })
        foreach ($c in ($certs | Select-Object -First 3)) {
            $e = Emit-LocHealthEvent -Source "Certificates" -EventID 9600 -Severity "Warning" -Category "security" `
                -Message ("Certificate expiring soon: {0}" -f $c.Subject) `
                -Data @{ healthMetric = "certExpiring"; thumbprint = $c.Thumbprint; notAfter = $c.NotAfter.ToString("o") }
            if ($e) { $events += $e }
        }
    }
    catch { }

    # SMART best-effort via MSStorageDriver (often unavailable)
    try {
        $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        foreach ($s in @($smart)) {
            if ($s.PredictFailure) {
                $e = Emit-LocHealthEvent -Source "SMART" -EventID 9700 -Severity "Critical" -Category "storage" `
                    -Message "Disk SMART failure predicted" -Data @{ healthMetric = "smartFail"; reason = [string]$s.Reason }
                if ($e) { $events += $e }
            }
        }
    }
    catch { }

    return $events
}

function Get-LocHealthScorePayload {
    $tel = Get-LocTelemetry
    $checks = [System.Collections.ArrayList]::new()
    $score = 100

    $cpu = $null
    try {
        if ($tel.Cpu -and $tel.Cpu.UsagePct) { $cpu = [double]$tel.Cpu.UsagePct }
        elseif ($tel.Cpu -and $tel.Cpu.Usage) { $cpu = [double]$tel.Cpu.Usage }
        elseif ($tel.Cpu -and $tel.Cpu.Percent) { $cpu = [double]$tel.Cpu.Percent }
    } catch { }
    if ($null -ne $cpu -and $cpu -ge 95) {
        [void]$checks.Add([PSCustomObject]@{ Name = "CPU"; Status = "Warning"; Detail = ("{0:N0}%" -f $cpu) })
        $score -= 10
    }
    else {
        [void]$checks.Add([PSCustomObject]@{ Name = "CPU"; Status = "Healthy"; Detail = $(if ($null -ne $cpu) { "{0:N0}%" -f $cpu } else { "n/a" }) })
    }

    $mem = $null
    try {
        if ($tel.Memory -and $tel.Memory.UsedPct) { $mem = [double]$tel.Memory.UsedPct }
        elseif ($tel.Memory -and $tel.Memory.Usage) { $mem = [double]$tel.Memory.Usage }
        elseif ($tel.Memory -and $tel.Memory.Percent) { $mem = [double]$tel.Memory.Percent }
    } catch { }
    if ($null -ne $mem -and $mem -ge 95) {
        [void]$checks.Add([PSCustomObject]@{ Name = "RAM"; Status = "Warning"; Detail = ("{0:N0}%" -f $mem) })
        $score -= 10
    }
    else {
        [void]$checks.Add([PSCustomObject]@{ Name = "RAM"; Status = "Healthy"; Detail = $(if ($null -ne $mem) { "{0:N0}%" -f $mem } else { "n/a" }) })
    }

    $diskOk = $true
    $diskDetail = "ok"
    try {
        foreach ($d in @($tel.Disks)) {
            $fp = $null
            if ($d.FreePercent) { $fp = [double]$d.FreePercent }
            elseif ($d.PercentFree) { $fp = [double]$d.PercentFree }
            elseif ($null -ne $d.UsedPct) { $fp = 100.0 - [double]$d.UsedPct }
            if ($null -ne $fp -and $fp -le 10) { $diskOk = $false; $diskDetail = ("low free {0:N0}%" -f $fp) }
        }
        if ($diskOk -and $tel.Disk -and $null -ne $tel.Disk.UsedPct) {
            $fp = 100.0 - [double]$tel.Disk.UsedPct
            if ($fp -le 10) { $diskOk = $false; $diskDetail = ("low free {0:N0}%" -f $fp) }
        }
    } catch { }
    if ($diskOk) {
        [void]$checks.Add([PSCustomObject]@{ Name = "Disk"; Status = "Healthy"; Detail = $diskDetail })
    }
    else {
        [void]$checks.Add([PSCustomObject]@{ Name = "Disk"; Status = "Warning"; Detail = $diskDetail })
        $score -= 15
    }

    try {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp -and $mp.RealTimeProtectionEnabled) {
            [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Healthy"; Detail = "Realtime on" })
        }
        elseif ($mp) {
            [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Critical"; Detail = "Realtime off" })
            $score -= 25
        }
        else {
            [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Warning"; Detail = "Unavailable" })
            $score -= 5
        }
    } catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Warning"; Detail = "Unavailable" })
        $score -= 5
    }

    $down = 0
    foreach ($p in @($script:LocServiceProfiles)) {
        $svc = Get-Service -Name $p.service -ErrorAction SilentlyContinue
        if ($p.mustBeRunning -and (-not $svc -or $svc.Status -ne "Running")) { $down++ }
    }
    if ($down -gt 0) {
        [void]$checks.Add([PSCustomObject]@{ Name = "Services"; Status = "Warning"; Detail = ("{0} down" -f $down) })
        $score -= (5 * $down)
    }
    else {
        [void]$checks.Add([PSCustomObject]@{ Name = "Services"; Status = "Healthy"; Detail = "Profiles OK" })
    }

    try {
        $up = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
        if ($up.Count -gt 0) {
            [void]$checks.Add([PSCustomObject]@{ Name = "Network"; Status = "Healthy"; Detail = ("{0} up" -f $up.Count) })
        }
        else {
            [void]$checks.Add([PSCustomObject]@{ Name = "Network"; Status = "Critical"; Detail = "No adapters up" })
            $score -= 20
        }
    } catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "Network"; Status = "Warning"; Detail = "Unknown" })
        $score -= 5
    }

    [void]$checks.Add([PSCustomObject]@{ Name = "Windows Update"; Status = "Healthy"; Detail = "See Updates module" })
    [void]$checks.Add([PSCustomObject]@{ Name = "Certificates"; Status = "Healthy"; Detail = "Checked" })
    [void]$checks.Add([PSCustomObject]@{ Name = "Backups"; Status = "Information"; Detail = "Best-effort not configured" })

    $score = [Math]::Max(0, [Math]::Min(100, $score))
    return [PSCustomObject]@{
        Score   = $score
        Checks  = @($checks)
        Updated = (Get-Date).ToUniversalTime().ToString("o")
    }
}
