# notifications/Teams.ps1 - Incoming webhook

function Send-LocNotifyTeams {
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

        $payload = @{
            "@type"    = "MessageCard"
            "@context" = "https://schema.org/extensions"
            summary    = [string]$Alert.Title
            themeColor = if ($Alert.Severity -eq "Critical") { "FF0000" } elseif ($Alert.Severity -eq "Warning") { "FFA500" } else { "0078D4" }
            title      = [string]$Alert.Title
            text       = [string]$Alert.Message
        } | ConvertTo-Json -Depth 5 -Compress

        Invoke-RestMethod -Uri ([string]$url) -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop | Out-Null
        return @{ Success = $true; Message = "sent" }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Teams" -Level "WARN" -Message $_.Exception.Message
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}
