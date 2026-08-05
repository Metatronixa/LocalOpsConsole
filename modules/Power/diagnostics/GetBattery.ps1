try {
    $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if (-not $batt) {
        return New-ApiResult -Success $true -Message "No battery detected (desktop?)" -Data ([PSCustomObject]@{
            Present = $false
            ChargePct = $null
            Status = "N/A"
        })
    }
    $b = $batt | Select-Object -First 1
    return New-ApiResult -Success $true -Message "Battery status" -Data ([PSCustomObject]@{
        Present      = $true
        Name         = $b.Name
        ChargePct    = $b.EstimatedChargeRemaining
        Status       = [string]$b.BatteryStatus
        EstimatedRun = $b.EstimatedRunTime
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
