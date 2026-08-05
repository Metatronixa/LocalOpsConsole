# RunSpeedTest.ps1 — opt-in download speed test (15s hard timeout)
try {
    $urls = @(
        "https://speed.cloudflare.com/__down?bytes=2000000",
        "https://raw.githubusercontent.com/github/explore/main/README.md"
    )

    $latency = Invoke-LocFastPing -Target "1.1.1.1" -Count 2 -TimeoutMs 1200
    $downloadMbps = $null
    $bytes = 0
    $elapsedSec = 0
    $usedUrl = $null
    $startAll = Get-Date

    foreach ($url in $urls) {
        if (((Get-Date) - $startAll).TotalSeconds -gt 14) { break }
        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Timeout = 12000
            $req.UserAgent = "LocalOpsConsole/SpeedTest"
            $start = Get-Date
            $resp = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $buffer = New-Object byte[] 65536
            $total = 0
            while ($true) {
                if (((Get-Date) - $startAll).TotalSeconds -gt 15) { break }
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

    if ($null -eq $downloadMbps) {
        return New-ApiResult -Success $false -Message "Speed test timed out or failed" -Data ([PSCustomObject]@{
            DownloadMbps = $null
            LatencyMs    = $latency.AvgMs
            Bytes        = $bytes
        })
    }

    return New-ApiResult -Success $true -Message ("Download ~{0} Mbps" -f $downloadMbps) -Data ([PSCustomObject]@{
        DownloadMbps = $downloadMbps
        LatencyMs    = $latency.AvgMs
        Bytes        = $bytes
        DurationSec  = [math]::Round($elapsedSec, 2)
        SourceUrl    = $usedUrl
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
