# System CPU diagnostic
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $usage = [int]$cpu.LoadPercentage
    if ($null -eq $cpu.LoadPercentage) {
        $perf = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        if ($perf) { $usage = [math]::Round($perf.CounterSamples[0].CookedValue, 0) }
    }

    return New-ApiResult -Success $true -Message "CPU telemetry" -Data ([PSCustomObject]@{
        Name     = $cpu.Name
        Cores    = $cpu.NumberOfCores
        Logical  = $cpu.NumberOfLogicalProcessors
        UsagePct = $usage
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
