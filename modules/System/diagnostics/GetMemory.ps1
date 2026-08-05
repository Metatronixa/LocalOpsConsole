# System memory diagnostic
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $totalKB = [double]$os.TotalVisibleMemorySize
    $freeKB = [double]$os.FreePhysicalMemory
    $usedKB = $totalKB - $freeKB
    $totalGB = [math]::Round($totalKB / 1MB, 2)
    $usedGB = [math]::Round($usedKB / 1MB, 2)
    $freeGB = [math]::Round($freeKB / 1MB, 2)
    $usedPct = if ($totalKB -gt 0) { [math]::Round(($usedKB / $totalKB) * 100, 0) } else { 0 }

    return New-ApiResult -Success $true -Message "Memory telemetry" -Data ([PSCustomObject]@{
        TotalGB = $totalGB
        UsedGB  = $usedGB
        FreeGB  = $freeGB
        UsedPct = $usedPct
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
