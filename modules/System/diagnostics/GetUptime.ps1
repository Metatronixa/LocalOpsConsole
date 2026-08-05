# System uptime + pending reboot
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $boot = $os.LastBootUpTime
    $uptime = (Get-Date) - $boot
    $formatted = "{0}d {1:D2}h {2:D2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

    $pending = $false
    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    foreach ($k in $rebootKeys) {
        if ($k -like "*PendingFileRenameOperations") {
            $val = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($val.PendingFileRenameOperations) { $pending = $true; break }
        }
        elseif (Test-Path $k) { $pending = $true; break }
    }

    return New-ApiResult -Success $true -Message "Uptime telemetry" -Data ([PSCustomObject]@{
        ComputerName    = $env:COMPUTERNAME
        LastBoot        = $boot.ToString("yyyy-MM-dd HH:mm:ss")
        UptimeFormatted = $formatted
        PendingReboot   = $pending
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
