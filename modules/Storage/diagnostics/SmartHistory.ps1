# Storage/diagnostics/SmartHistory.ps1
try {
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $items = @()
    foreach ($d in $disks) {
        $health = [string]$d.HealthStatus
        $items += [PSCustomObject]@{
            FriendlyName  = $d.FriendlyName
            MediaType     = [string]$d.MediaType
            SizeGB        = [math]::Round([double]$d.Size / 1GB, 2)
            HealthStatus  = $health
            Operational   = [string]$d.OperationalStatus
            BusType       = [string]$d.BusType
            SerialNumber  = $d.SerialNumber
            SnapshotAt    = (Get-Date).ToUniversalTime().ToString("o")
        }
    }

    $histDir = Join-Path (Get-LocRoot) "data\storage"
    if (-not (Test-Path $histDir)) { New-Item -ItemType Directory -Path $histDir -Force | Out-Null }
    $histFile = Join-Path $histDir "smart-history.jsonl"
    Add-Content -Path $histFile -Value ((@{ ts = (Get-Date).ToUniversalTime().ToString("o"); disks = $items } | ConvertTo-Json -Compress -Depth 5)) -Encoding UTF8

    $history = @()
    if (Test-Path $histFile) {
        $history = @(Get-Content $histFile -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $_ })
    }

    New-ApiResult -Success $true -Message "SMART / disk health history" -Data @{
        Current = @($items)
        History = @($history)
        Unhealthy = @($items | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne "Healthy" })
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
