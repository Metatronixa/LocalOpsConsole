# Updates/diagnostics/PendingReboot.ps1
try {
    $reasons = @()
    $checks = @{
        "WU RebootRequired" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        "CBS RebootPending" = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        "Pending file renames" = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    }
    $pending = $false
    if (Test-Path $checks["WU RebootRequired"]) { $pending = $true; $reasons += "Windows Update" }
    if (Test-Path $checks["CBS RebootPending"]) { $pending = $true; $reasons += "Component Based Servicing" }
    $sm = Get-ItemProperty -Path $checks["Pending file renames"] -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sm -and $sm.PendingFileRenameOperations) { $pending = $true; $reasons += "PendingFileRenameOperations" }

    New-ApiResult -Success $true -Message $(if ($pending) { "Reboot pending" } else { "No reboot pending" }) -Data @{
        PendingReboot = $pending
        Reasons       = $reasons
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
