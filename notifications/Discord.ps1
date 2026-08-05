# notifications/Discord.ps1 - Incoming webhook

function Send-LocNotifyDiscord {
    param(
        [object]$Alert,
        [object]$Incident,
        [object]$Config = $null
    )
    try {
        if (-not $Config) {
            return @{ Success = $false; Message = "not configured" }
        }

        $url = $null
        if ($Config -is [hashtable]) { $url = $Config["webhookUrl"] }
        elseif ($Config) { $url = $Config.webhookUrl }
        if (-not $url) {
            return @{ Success = $false; Message = "not configured" }
        }

        $content = "**[$($Alert.Severity)] $($Alert.Title)**`n$($Alert.Message)"
        $payload = @{ content = $content } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri ([string]$url) -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop | Out-Null
        return @{ Success = $true; Message = "sent" }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Discord" -Level "WARN" -Message $_.Exception.Message
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}
