param([int]$MaxEvents = 20)

try {
    $events = @()
    $logs = @(
        "Microsoft-Windows-PrintService/Operational",
        "Microsoft-Windows-PrintService/Admin",
        "System"
    )

    foreach ($log in $logs) {
        if ($events.Count -ge $MaxEvents) { break }
        try {
            $batch = Get-WinEvent -FilterHashtable @{
                LogName   = $log
                Level     = 1, 2
                StartTime = (Get-Date).AddDays(-3)
            } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProviderName -match 'Print|Spooler' -or $_.Message -match 'print|spooler'
                }
            $events += @($batch)
        }
        catch { Write-Debug $_.Exception.Message }
    }

    $data = @($events |
        Sort-Object TimeCreated -Descending |
        Select-Object -First $MaxEvents |
        ForEach-Object {
            $msg = if ($_.Message) { $_.Message.Substring(0, [Math]::Min(240, $_.Message.Length)) } else { "" }
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                LogName     = $_.LogName
                Id          = $_.Id
                Level       = [string]$_.LevelDisplayName
                Provider    = $_.ProviderName
                Message     = $msg
            }
        })

    return New-ApiResult -Success $true -Message ("{0} print event(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
