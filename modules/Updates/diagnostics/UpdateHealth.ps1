# Updates/diagnostics/UpdateHealth.ps1
try {
    $pendingReboot = $false
    $rebootReasons = @()
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        $pendingReboot = $true; $rebootReasons += "WindowsUpdate RebootRequired"
    }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $pendingReboot = $true; $rebootReasons += "CBS RebootPending"
    }
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations") {
        $pendingReboot = $true; $rebootReasons += "PendingFileRenameOperations"
    }

    $services = Get-Service wuauserv, bits, cryptsvc, msiserver, usosvc -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status; StartType = [string]$_.StartType }
    }

    # Servicing stack / CBS hint
    $cbs = @(Get-WinEvent -FilterHashtable @{ LogName = "Setup"; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 2, 3, 4 } | Select-Object -First 15 |
        ForEach-Object {
            [PSCustomObject]@{
                Time = $_.TimeCreated.ToUniversalTime().ToString("o")
                Id   = $_.Id
                Message = if ($_.Message.Length -gt 200) { $_.Message.Substring(0, 200) + "…" } else { $_.Message }
            }
        })

    $failures = @()
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $count = $searcher.GetTotalHistoryCount()
        if ($count -gt 0) {
            $take = [Math]::Min(40, $count)
            $hist = $searcher.QueryHistory(0, $take)
            for ($i = 0; $i -lt $hist.Count; $i++) {
                $h = $hist.Item($i)
                # ResultCode 4 = Failed
                if ([int]$h.ResultCode -eq 4 -or [int]$h.ResultCode -eq 5) {
                    $failures += [PSCustomObject]@{
                        Title      = $h.Title
                        Date       = $h.Date.ToString("yyyy-MM-dd HH:mm:ss")
                        ResultCode = [int]$h.ResultCode
                        HResult    = ("0x{0:X8}" -f $h.HResult)
                    }
                }
            }
        }
    }
    catch {
        $comError = $_.Exception.Message
    }

    $score = 100
    if ($pendingReboot) { $score -= 15 }
    $stopped = @($services | Where-Object { $_.Name -eq "wuauserv" -and $_.Status -ne "Running" })
    if ($stopped.Count) { $score -= 25 }
    if ($failures.Count -ge 3) { $score -= 20 } elseif ($failures.Count -gt 0) { $score -= 10 }
    if ($score -lt 0) { $score = 0 }

    New-ApiResult -Success $true -Message "Windows Update health" -Data @{
        Score            = $score
        PendingReboot    = $pendingReboot
        RebootReasons    = $rebootReasons
        Services         = @($services)
        FailureHistory   = @($failures)
        ServicingEvents  = @($cbs)
        Note             = $comError
        Status           = if ($score -ge 80) { "Healthy" } elseif ($score -ge 60) { "Warning" } else { "Critical" }
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
