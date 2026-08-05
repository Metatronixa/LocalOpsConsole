param(
    [int]$MaxEvents = 50,
    [string]$LogName = "System,Application"
)
try {
    $logs = $LogName.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $events = @()
    foreach ($log in $logs) {
        try {
            $events += Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2 } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
                Select-Object -First $MaxEvents
        }
        catch { }
    }
    $data = @($events | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents | ForEach-Object {
        [PSCustomObject]@{
            TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            LogName     = $_.LogName
            Id          = $_.Id
            Level       = [string]$_.LevelDisplayName
            Provider    = $_.ProviderName
            Message     = if ($_.Message) { $_.Message.Substring(0, [Math]::Min(240, $_.Message.Length)) } else { "" }
        }
    })
    return New-ApiResult -Success $true -Message ("{0} error/critical event(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
