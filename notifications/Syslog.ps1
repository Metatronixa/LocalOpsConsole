# notifications/Syslog.ps1 - UDP/TCP syslog (RFC5424-ish)

function Send-LocNotifySyslog {
    param(
        [object]$Alert,
        [object]$Incident,
        [object]$Config = $null
    )
    try {
        if (-not $Config) {
            return @{ Success = $false; Message = "not configured" }
        }

        $hostName = $null; $port = 514; $proto = "UDP"
        if ($Config -is [hashtable]) {
            $hostName = $Config["host"]
            if ($Config["port"]) { $port = [int]$Config["port"] }
            if ($Config["protocol"]) { $proto = [string]$Config["protocol"] }
        }
        elseif ($Config) {
            $hostName = $Config.host
            if ($Config.port) { $port = [int]$Config.port }
            if ($Config.protocol) { $proto = [string]$Config.protocol }
        }
        if (-not $hostName) {
            return @{ Success = $false; Message = "not configured" }
        }

        $pri = 14
        if ($Alert.Severity -eq "Critical") { $pri = 10 }
        elseif ($Alert.Severity -eq "Warning") { $pri = 12 }
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $msg = "<$pri>1 $ts $env:COMPUTERNAME LocalOpsConsole - - - [$($Alert.Severity)] $($Alert.Title): $($Alert.Message)"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)

        if ($proto -match '(?i)tcp') {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect($hostName, $port)
            $stream = $client.GetStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close(); $client.Close()
        }
        else {
            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Send($bytes, $bytes.Length, $hostName, $port) | Out-Null
            $udp.Close()
        }
        return @{ Success = $true; Message = "sent" }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Syslog" -Level "WARN" -Message $_.Exception.Message
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}
