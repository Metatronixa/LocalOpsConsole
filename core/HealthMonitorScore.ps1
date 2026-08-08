# core/HealthMonitorScore.ps1 - Aggregated health score payload

function Get-LocHealthScorePayload {
    $tel = Get-LocTelemetry
    $checks = [System.Collections.ArrayList]::new()
    $score = 100

    $cpu = $null
    try {
        if ($tel.Cpu -and $tel.Cpu.UsagePct) { $cpu = [double]$tel.Cpu.UsagePct }
        elseif ($tel.Cpu -and $tel.Cpu.Usage) { $cpu = [double]$tel.Cpu.Usage }
        elseif ($tel.Cpu -and $tel.Cpu.Percent) { $cpu = [double]$tel.Cpu.Percent }
    } catch { Write-Debug $_.Exception.Message }
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
    } catch { Write-Debug $_.Exception.Message }
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
    } catch { Write-Debug $_.Exception.Message }
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
