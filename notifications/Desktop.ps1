# notifications/Desktop.ps1 - Desktop toast / balloon

function Send-LocNotifyDesktop {
    param(
        [object]$Alert,
        [object]$Incident,
        [object]$Config = $null
    )
    try {
        $title = if ($Alert.Title) { [string]$Alert.Title } else { "LocalOpsConsole" }
        $msg = if ($Alert.Message) { [string]$Alert.Message } else { $title }

        if (Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue) {
            Import-Module BurntToast -ErrorAction SilentlyContinue
            if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
                New-BurntToastNotification -Text $title, $msg -ErrorAction Stop | Out-Null
                return @{ Success = $true; Message = "sent" }
            }
        }

        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $icon = [System.Windows.Forms.ToolTipIcon]::Info
        if ($Alert.Severity -eq "Critical") { $icon = [System.Windows.Forms.ToolTipIcon]::Error }
        elseif ($Alert.Severity -eq "Warning") { $icon = [System.Windows.Forms.ToolTipIcon]::Warning }
        $notify.ShowBalloonTip(5000, $title, $msg, $icon)
        Start-Sleep -Milliseconds 600
        $notify.Dispose()
        return @{ Success = $true; Message = "sent" }
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "Desktop" -Level "WARN" -Message $_.Exception.Message
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}
