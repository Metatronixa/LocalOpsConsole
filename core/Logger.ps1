# core/Logger.ps1 - File + in-memory ring buffer logging

$script:LocLogRing = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$script:LocLogMax = 500
$script:LocLogDir = $null

function Initialize-LocLogger {
    param([string]$RootPath)

    $script:LocLogDir = Join-Path $RootPath "logs"
    if (-not (Test-Path $script:LocLogDir)) {
        New-Item -ItemType Directory -Path $script:LocLogDir -Force | Out-Null
    }

    $settings = Get-LocSettings
    if ($settings -and $settings.logRetentionDays) {
        $cutoff = (Get-Date).AddDays(-[int]$settings.logRetentionDays)
        Get-ChildItem -Path $script:LocLogDir -Filter "*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Write-LocLog {
    param(
        [string]$Module = "CORE",
        [string]$Action = "-",
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO",
        [string]$Message = ""
    )

    $time = Get-Date -Format "HH:mm:ss"
    $date = Get-Date -Format "yyyy-MM-dd"
    $line = "$time | $($Module.ToUpper()) | $Action | $Level | $Message"

    $entry = [PSCustomObject]@{
        Time    = $time
        Module  = $Module.ToUpper()
        Action  = $Action
        Level   = $Level
        Message = $Message
        Line    = $line
    }

    [void]$script:LocLogRing.Add($entry)
    while ($script:LocLogRing.Count -gt $script:LocLogMax) {
        $script:LocLogRing.RemoveAt(0)
    }

    if ($script:LocLogDir) {
        $logFile = Join-Path $script:LocLogDir "$date.log"
        try {
            Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch { }
    }

    # Do not emit to pipeline (avoids contaminating action results)
}

function Get-LocLogTail {
    param([int]$Lines = 100)

    $all = @($script:LocLogRing.ToArray())
    if ($all.Count -eq 0) { return @() }
    $start = [Math]::Max(0, $all.Count - $Lines)
    return $all[$start..($all.Count - 1)]
}
