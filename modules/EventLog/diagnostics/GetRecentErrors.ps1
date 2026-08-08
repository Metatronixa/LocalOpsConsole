# EventLog/diagnostics/GetRecentErrors.ps1 — bounded, fast query
param(
    [int]$MaxEvents = 40,
    [int]$Hours = 48,
    [string]$LogName = "System,Application"
)

try {
    if ($MaxEvents -lt 1) { $MaxEvents = 40 }
    if ($MaxEvents -gt 100) { $MaxEvents = 100 }
    if ($Hours -lt 1) { $Hours = 48 }
    if ($Hours -gt 168) { $Hours = 168 }

    $logs = @($LogName.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    # Security log is huge and often needs elevation — skip unless explicitly requested
    $start = (Get-Date).AddHours(-$Hours)
    $perLog = [Math]::Max(10, [Math]::Ceiling($MaxEvents / [Math]::Max(1, $logs.Count)))
    $events = [System.Collections.ArrayList]::new()

    foreach ($log in $logs) {
        try {
            $batch = @(Get-WinEvent -FilterHashtable @{
                    LogName   = $log
                    Level     = 1, 2
                    StartTime = $start
                } -MaxEvents $perLog -ErrorAction Stop)
            foreach ($e in $batch) { [void]$events.Add($e) }
        }
        catch { Write-Debug $_.Exception.Message }
    }

    $data = @($events | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents | ForEach-Object {
            $msg = ""
            try {
                if ($_.Message) {
                    $msg = $_.Message.Substring(0, [Math]::Min(200, $_.Message.Length))
                }
            }
            catch { Write-Debug $_.Exception.Message }
            [PSCustomObject]@{
                TimeCreated = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                LogName     = $_.LogName
                Id          = $_.Id
                Level       = [string]$_.LevelDisplayName
                Provider    = $_.ProviderName
                Message     = $msg
            }
        })

    New-ApiResult -Success $true -Message ("{0} error/critical event(s) (last {1}h)" -f $data.Count, $Hours) -Data $data
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
