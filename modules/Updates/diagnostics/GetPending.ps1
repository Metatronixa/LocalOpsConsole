try {
    $pendingReboot = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $pendingReboot = $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $pendingReboot = $true }

    $wu = Get-Service wuauserv, bits, cryptsvc, msiserver -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status; StartType = [string]$_.StartType }
    }

    $lastSuccess = $null
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()
        if ($historyCount -gt 0) {
            $hist = $searcher.QueryHistory(0, 1)
            if ($hist.Count -gt 0) { $lastSuccess = $hist.Item(0).Date.ToString("yyyy-MM-dd HH:mm:ss") }
        }
        $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
        $pending = @()
        for ($i = 0; $i -lt $result.Updates.Count -and $i -lt 25; $i++) {
            $u = $result.Updates.Item($i)
            $pending += [PSCustomObject]@{ Title = $u.Title; IsDownloaded = $u.IsDownloaded; SizeMB = [math]::Round($u.MaxDownloadSize / 1MB, 1) }
        }
    }
    catch {
        $pending = @()
        $comError = $_.Exception.Message
    }

    return New-ApiResult -Success $true -Message "Windows Update status" -Data ([PSCustomObject]@{
        PendingReboot   = $pendingReboot
        LastHistoryDate = $lastSuccess
        PendingUpdates  = @($pending)
        PendingCount    = @($pending).Count
        Services        = @($wu)
        Note            = $comError
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
