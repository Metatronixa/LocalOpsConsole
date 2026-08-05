# notifications/Email.ps1 - SMTP email

function Send-LocNotifyEmail {
    param(
        [object]$Alert,
        [object]$Incident,
        [object]$Config = $null
    )
    try {
        if (-not $Config) {
            return @{ Success = $false; Message = "not configured" }
        }

        $smtp = $null; $to = $null; $from = $null
        if ($Config -is [hashtable]) {
            $smtp = $Config["smtpServer"]; $to = $Config["to"]; $from = $Config["from"]
            $port = if ($Config["port"]) { [int]$Config["port"] } else { 25 }
            $user = $Config["username"]; $pass = $Config["password"]
        }
        else {
            $smtp = $Config.smtpServer; $to = $Config.to; $from = $Config.from
            $port = if ($Config.port) { [int]$Config.port } else { 25 }
            $user = $Config.username; $pass = $Config.password
        }
        if (-not $smtp -or -not $to -or -not $from) {
            return @{ Success = $false; Message = "not configured" }
        }

        $subject = "[$($Alert.Severity)] $($Alert.Title)"
        $body = @"
$($Alert.Message)

Severity: $($Alert.Severity)
Category: $($Alert.Category)
Incident: $($Alert.IncidentId)
Host: $env:COMPUTERNAME
Time: $($Alert.Timestamp)
"@
        $params = @{
            SmtpServer = [string]$smtp
            Port       = $port
            To         = [string]$to
            From       = [string]$from
            Subject    = $subject
            Body       = $body
        }
        if ($user -and $pass) {
            $secure = ConvertTo-SecureString ([string]$pass) -AsPlainText -Force
            $params.Credential = New-Object System.Management.Automation.PSCredential ([string]$user, $secure)
        }
        Send-MailMessage @params -ErrorAction Stop
        return @{ Success = $true; Message = "sent" }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Email" -Level "WARN" -Message $_.Exception.Message
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}
