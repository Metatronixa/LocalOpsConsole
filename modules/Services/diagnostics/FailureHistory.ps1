# Services/diagnostics/FailureHistory.ps1
param([string]$Name = "", [int]$Hours = 72)

try {
    $since = (Get-Date).AddHours(-[Math]::Abs($Hours))
    $filter = @{ LogName = "System"; StartTime = $since; Id = 7000, 7001, 7009, 7011, 7022, 7023, 7024, 7031, 7034 }
    $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue | Select-Object -First 200)

    $items = @()
    foreach ($e in $events) {
        $msg = $e.Message
        if ($Name -and $msg -notmatch [regex]::Escape($Name)) { continue }
        $items += [PSCustomObject]@{
            TimeCreated = $e.TimeCreated.ToUniversalTime().ToString("o")
            Id          = $e.Id
            Level       = $e.LevelDisplayName
            Provider    = $e.ProviderName
            Message     = if ($msg.Length -gt 280) { $msg.Substring(0, 280) + "…" } else { $msg }
        }
    }

    # Restart counts via Service Control Manager 7036 running transitions approximate
    $restarts = @{}
    foreach ($e in $events | Where-Object { $_.Id -eq 7036 -or $_.Id -eq 7031 }) {
        if ($e.Message -match "The (.+) service") {
            $n = $Matches[1]
            if (-not $restarts.ContainsKey($n)) { $restarts[$n] = 0 }
            $restarts[$n]++
        }
    }

    New-ApiResult -Success $true -Message "Service failure history" -Data @{
        Hours         = $Hours
        Events        = @($items)
        RestartHints  = @($restarts.GetEnumerator() | ForEach-Object { [PSCustomObject]@{ Name = $_.Key; Count = $_.Value } })
        EventCount    = $items.Count
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
