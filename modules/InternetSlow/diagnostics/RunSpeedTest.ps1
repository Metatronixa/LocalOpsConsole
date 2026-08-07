# RunSpeedTest.ps1 — opt-in download + upload speed test (hard timeout)
try {
    $urls = @(
        "https://speed.cloudflare.com/__down?bytes=2000000",
        "https://raw.githubusercontent.com/github/explore/main/README.md"
    )

    $latency = Invoke-LocFastPing -Target "1.1.1.1" -Count 2 -TimeoutMs 1200
    $downloadMbps = $null
    $uploadMbps = $null
    $bytes = 0
    $uploadBytes = 0
    $elapsedSec = 0
    $uploadSec = 0
    $usedUrl = $null
    $startAll = Get-Date

    foreach ($url in $urls) {
        if (((Get-Date) - $startAll).TotalSeconds -gt 10) { break }
        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Timeout = 9000
            $req.UserAgent = "LocalOpsConsole/SpeedTest"
            $start = Get-Date
            $resp = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $buffer = New-Object byte[] 65536
            $total = 0
            while ($true) {
                if (((Get-Date) - $startAll).TotalSeconds -gt 11) { break }
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $total += $read
                if ($total -ge 5000000) { break }
            }
            $stream.Close()
            $resp.Close()
            $elapsedSec = [math]::Max(0.001, ((Get-Date) - $start).TotalSeconds)
            if ($total -gt 100000) {
                $bytes = $total
                $usedUrl = $url
                $downloadMbps = [math]::Round((($bytes * 8) / $elapsedSec) / 1000000, 2)
                break
            }
        }
        catch { continue }
    }

    # Cloudflare upload probe (bounded)
    if (((Get-Date) - $startAll).TotalSeconds -lt 14) {
        try {
            $payload = New-Object byte[] 250000
            $rng = [System.Random]::new()
            $rng.NextBytes($payload)
            $upUrl = "https://speed.cloudflare.com/__up"
            $upStart = Get-Date
            $wc = New-Object System.Net.WebClient
            $wc.Headers["User-Agent"] = "LocalOpsConsole/SpeedTest"
            try {
                $null = $wc.UploadData($upUrl, "POST", $payload)
            }
            finally { $wc.Dispose() }
            $uploadSec = [math]::Max(0.001, ((Get-Date) - $upStart).TotalSeconds)
            $uploadBytes = $payload.Length
            $uploadMbps = [math]::Round((($uploadBytes * 8) / $uploadSec) / 1000000, 2)
        }
        catch {
            $uploadMbps = $null
        }
    }

    if ($null -eq $downloadMbps -and $null -eq $uploadMbps) {
        return New-ApiResult -Success $false -Message "Speed test timed out or failed" -Data ([PSCustomObject]@{
            DownloadMbps = $null
            UploadMbps   = $null
            LatencyMs    = $latency.AvgMs
            Bytes        = $bytes
        })
    }

    $msgParts = @()
    if ($null -ne $downloadMbps) { $msgParts += ("Down ~{0} Mbps" -f $downloadMbps) }
    if ($null -ne $uploadMbps) { $msgParts += ("Up ~{0} Mbps" -f $uploadMbps) }

    return New-ApiResult -Success $true -Message ($msgParts -join " · ") -Data ([PSCustomObject]@{
        DownloadMbps = $downloadMbps
        UploadMbps   = $uploadMbps
        LatencyMs    = $latency.AvgMs
        Bytes        = $bytes
        UploadBytes  = $uploadBytes
        DurationSec  = [math]::Round($elapsedSec, 2)
        UploadSec    = [math]::Round($uploadSec, 2)
        SourceUrl    = $usedUrl
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
