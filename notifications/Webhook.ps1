# notifications/Webhook.ps1 - Generic JSON webhook

function Send-LocNotifyWebhook {
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
        if ($Config -is [hashtable]) { $url = $Config["url"] }
        elseif ($Config) { $url = $Config.url }
        if (-not $url) {
            return @{ Success = $false; Message = "not configured" }
        }

        $payload = @{
            alert    = $Alert
            incident = @{
                Id       = $Incident.Id
                Title    = $Incident.Title
                Severity = $Incident.Severity
                Score    = $Incident.Score
                Category = $Incident.Category
            }
            host      = $env:COMPUTERNAME
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -Depth 8 -Compress

        Invoke-RestMethod -Uri ([string]$url) -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop | Out-Null
        return @{ Success = $true; Message = "sent" }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Webhook" -Level "WARN" -Message $_.Exception.Message
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}
