try {
    $summary = @()
    foreach ($log in @("System", "Application", "Security")) {
        try {
            $count = (Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2; StartTime = (Get-Date).AddHours(-24) } -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        catch { $count = 0 }
        $summary += [PSCustomObject]@{
            LogName          = $log
            ErrorsLast24h    = $count
        }
    }
    return New-ApiResult -Success $true -Message "Event log summary (24h)" -Data @($summary)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
