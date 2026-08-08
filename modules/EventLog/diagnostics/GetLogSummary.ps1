# EventLog/diagnostics/GetLogSummary.ps1 — capped counts (never unbounded Measure-Object)
param(
    [int]$Hours = 24,
    [int]$SampleMax = 200
)

try {
    if ($Hours -lt 1) { $Hours = 24 }
    if ($SampleMax -lt 50) { $SampleMax = 50 }
    if ($SampleMax -gt 500) { $SampleMax = 500 }

    $start = (Get-Date).AddHours(-$Hours)
    $summary = [System.Collections.ArrayList]::new()

    foreach ($log in @("System", "Application", "Security")) {
        $count = 0
        $capped = $false
        $accessible = $true
        $note = ""
        try {
            # Cap retrieval — never pipe entire log into Measure-Object
            $batch = @(Get-WinEvent -FilterHashtable @{
                    LogName   = $log
                    Level     = 1, 2
                    StartTime = $start
                } -MaxEvents $SampleMax -ErrorAction Stop)
            $count = $batch.Count
            if ($count -ge $SampleMax) {
                $capped = $true
                $note = ">= $SampleMax (sample capped)"
            }
        }
        catch {
            $accessible = $false
            $note = $_.Exception.Message
            if ($note -match 'Access|denied|Unauthorized') {
                $note = "Access denied (try elevated)"
            }
        }

        [void]$summary.Add([PSCustomObject]@{
                LogName       = $log
                ErrorsLast24h = $count
                Hours         = $Hours
                Capped        = $capped
                Accessible    = $accessible
                Note          = $note
            })
    }

    New-ApiResult -Success $true -Message ("Event log summary (last {0}h, sample max {1})" -f $Hours, $SampleMax) -Data @($summary)
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
