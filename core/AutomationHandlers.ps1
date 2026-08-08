# core/AutomationHandlers.ps1 - Opt-in remediation handler table

$script:LocAutomationHandlers = @{
    "restart-service" = {
        param($Context)
        $svcName = $null
        if ($Context.Event -and $Context.Event.Data) {
            if ($Context.Event.Data -is [hashtable] -and $Context.Event.Data.ContainsKey("service")) {
                $svcName = [string]$Context.Event.Data["service"]
            }
            elseif ($Context.Event.Data.service) { $svcName = [string]$Context.Event.Data.service }
        }
        if (-not $svcName -and $Context.Rule -and $Context.Rule.automation -and $Context.Rule.automation.service) {
            $svcName = [string]$Context.Rule.automation.service
        }
        if (-not $svcName) { return @{ Success = $false; Message = "No service specified" } }
        try {
            Restart-Service -Name $svcName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne "Running") {
                return @{ Success = $false; Message = "Restarted $svcName but status is $($svc.Status)" }
            }
            return @{ Success = $true; Message = "Restarted and verified $svcName is Running" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "verify-service" = {
        param($Context)
        $svcName = $null
        if ($Context.Rule -and $Context.Rule.automation -and $Context.Rule.automation.service) {
            $svcName = [string]$Context.Rule.automation.service
        }
        if (-not $svcName) { return @{ Success = $false; Message = "No service specified" } }
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            $ok = ($svc.Status -eq "Running")
            return @{ Success = $ok; Message = "$svcName is $($svc.Status)" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "disk-cleanup" = {
        param($Context)
        $null = $Context
        try {
            $temp = $env:TEMP
            $removed = 0
            Get-ChildItem -Path $temp -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
                Select-Object -First 200 |
                ForEach-Object {
                    try { Remove-Item $_.FullName -Force -ErrorAction Stop; $removed++ } catch { Write-Debug $_.Exception.Message }
                }
            return @{ Success = $true; Message = "Removed $removed old temp file(s)" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "notify-only" = {
        param($Context)
        $null = $Context
        return @{ Success = $true; Message = "Notification-only playbook acknowledged" }
    }
    "clear-print-queue" = {
        param($Context)
        $null = $Context
        try {
            $removed = 0
            $printers = @(Get-Printer -ErrorAction SilentlyContinue)
            foreach ($p in $printers) {
                $jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue)
                foreach ($j in $jobs) {
                    try {
                        Remove-PrintJob -PrinterName $j.PrinterName -ID $j.Id -ErrorAction Stop
                        $removed++
                    }
                    catch { Write-Debug $_.Exception.Message }
                }
            }
            return @{ Success = $true; Message = "Cleared $removed print job(s) across $($printers.Count) printer(s)" }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "network-soft-repair" = {
        param($Context)
        $null = $Context
        try {
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
            return @{ Success = $true; Message = ("Network soft repair: {0}" -f ($steps -join " â†’ ")) }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    "restart-update-stack" = {
        param($Context)
        $null = $Context
        $names = @("wuauserv", "bits")
        $ok = @()
        $fail = @()
        foreach ($svcName in $names) {
            try {
                Restart-Service -Name $svcName -Force -ErrorAction Stop
                Start-Sleep -Seconds 1
                $svc = Get-Service -Name $svcName -ErrorAction Stop
                if ($svc.Status -eq "Running") {
                    $ok += $svcName
                }
                else {
                    $fail += "$svcName=$($svc.Status)"
                }
            }
            catch {
                $fail += "$svcName=$($_.Exception.Message)"
            }
        }
        if ($fail.Count -eq 0) {
            return @{ Success = $true; Message = ("Restarted update stack: {0}" -f ($ok -join ", ")) }
        }
        if ($ok.Count -gt 0) {
            return @{ Success = $false; Message = ("Partial update stack restart. OK: {0}; Failed: {1}" -f ($ok -join ", "), ($fail -join "; ")) }
        }
        return @{ Success = $false; Message = ("Update stack restart failed: {0}" -f ($fail -join "; ")) }
    }
    "capture-process-snapshot" = {
        param($Context)
        $null = $Context
        try {
            $procs = @(Get-Process -ErrorAction SilentlyContinue |
                Sort-Object -Property @{ Expression = 'CPU'; Descending = $true }, @{ Expression = 'WorkingSet64'; Descending = $true } |
                Select-Object -First 15)
            if ($procs.Count -eq 0) {
                return @{ Success = $true; Message = "No processes available for snapshot" }
            }
            $lines = foreach ($p in $procs) {
                $mb = [math]::Round(($p.WorkingSet64 / 1MB), 1)
                $cpu = if ($null -eq $p.CPU) { 0 } else { [math]::Round([double]$p.CPU, 1) }
                "{0}(pid={1},cpu={2}s,ws={3}MB)" -f $p.ProcessName, $p.Id, $cpu, $mb
            }
            return @{ Success = $true; Message = ("Top processes: {0}" -f ($lines -join "; ")) }
        }
        catch {
            return @{ Success = $false; Message = $_.Exception.Message }
        }
    }
}
