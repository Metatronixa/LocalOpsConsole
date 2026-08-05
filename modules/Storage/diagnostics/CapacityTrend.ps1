# Storage/diagnostics/CapacityTrend.ps1
try {
    $vols = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
    $items = @()
    foreach ($v in $vols) {
        $size = [double]$v.Size
        $free = [double]$v.FreeSpace
        $usedPct = if ($size -gt 0) { [math]::Round(100.0 * ($size - $free) / $size, 1) } else { 0 }
        $items += [PSCustomObject]@{
            Letter      = $v.DeviceID
            Label       = $v.VolumeName
            SizeGB      = [math]::Round($size / 1GB, 2)
            FreeGB      = [math]::Round($free / 1GB, 2)
            UsedPct     = $usedPct
            FileSystem  = $v.FileSystem
            Status      = if ($usedPct -ge 95) { "Critical" } elseif ($usedPct -ge 85) { "Warning" } else { "Healthy" }
            SnapshotAt  = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    # Persist lightweight history for trends
    $histDir = Join-Path (Get-LocRoot) "data\storage"
    if (-not (Test-Path $histDir)) { New-Item -ItemType Directory -Path $histDir -Force | Out-Null }
    $histFile = Join-Path $histDir "capacity-history.jsonl"
    $line = (@{ ts = (Get-Date).ToUniversalTime().ToString("o"); volumes = $items } | ConvertTo-Json -Compress -Depth 5)
    Add-Content -Path $histFile -Value $line -Encoding UTF8

    $history = @()
    if (Test-Path $histFile) {
        $history = @(Get-Content $histFile -Tail 30 -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $_ })
    }

    New-ApiResult -Success $true -Message "Capacity trend snapshot" -Data @{
        Current = @($items)
        History = @($history)
        Note    = "History stored locally in data/storage/capacity-history.jsonl"
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
