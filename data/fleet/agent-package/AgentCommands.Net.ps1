# AgentCommands.Net.ps1 - Network health and Windows Update handlers
if (-not $script:LocAgentHandlers) { $script:LocAgentHandlers = @{} }

$script:LocAgentHandlers['NetHealthSmoke'] = {
    param($r)
    $latencyMs = $null
    $pingOk = $false
    try {
        $pings = Test-Connection -ComputerName 1.1.1.1 -Count 3 -ErrorAction Stop
        $samples = @()
        foreach ($p in @($pings)) {
            if ($null -ne $p.ResponseTime) { $samples += [double]$p.ResponseTime }
            elseif ($null -ne $p.Latency) { $samples += [double]$p.Latency }
        }
        if ($samples.Count -gt 0) {
            $latencyMs = [math]::Round((($samples | Measure-Object -Average).Average), 1)
            $pingOk = $true
        }
    }
    catch {
        & $r.AddLog "Ping failed: $($_.Exception.Message)"
    }
    
    $downloadMbps = $null
    $downloadMs = $null
    $downloadOk = $false
    try {
        $bytes = 200000
        $url = "https://speed.cloudflare.com/__down?bytes=$bytes"
        $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc = New-Object System.Net.WebClient
        try {
            $null = $wc.DownloadData($url)
        }
        finally { $wc.Dispose() }
        $dlSw.Stop()
        $downloadMs = [int]$dlSw.ElapsedMilliseconds
        if ($downloadMs -gt 0) {
            $downloadMbps = [math]::Round((($bytes * 8.0) / ($downloadMs / 1000.0)) / 1000000.0, 2)
            $downloadOk = $true
        }
    }
    catch {
        & $r.AddLog "Download smoke failed: $($_.Exception.Message)"
    }
    
    $uploadMbps = $null
    $uploadMs = $null
    $uploadOk = $false
    try {
        $upBytes = 100000
        $r.Payload = New-Object byte[] $upBytes
        (New-Object System.Random).NextBytes($r.Payload)
        $upUrl = "https://speed.cloudflare.com/__up"
        $upSw = [System.Diagnostics.Stopwatch]::StartNew()
        $wcUp = New-Object System.Net.WebClient
        try {
            $null = $wcUp.UploadData($upUrl, 'POST', $r.Payload)
        }
        finally { $wcUp.Dispose() }
        $upSw.Stop()
        $uploadMs = [int]$upSw.ElapsedMilliseconds
        if ($uploadMs -gt 0) {
            $uploadMbps = [math]::Round((($upBytes * 8.0) / ($uploadMs / 1000.0)) / 1000000.0, 2)
            $uploadOk = $true
        }
    }
    catch {
        & $r.AddLog "Upload smoke failed: $($_.Exception.Message)"
    }
    
    $r.Data = @{
        InternetLatencyMs = $latencyMs
        PingOk            = $pingOk
        DownloadMbps      = $downloadMbps
        DownloadMs        = $downloadMs
        DownloadOk        = $downloadOk
        UploadMbps        = $uploadMbps
        UploadMs          = $uploadMs
        UploadOk          = $uploadOk
        ProbedAt          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $dlTxt = if ($downloadOk) { "$downloadMbps Mbps" } else { 'fail' }
    $upTxt = if ($uploadOk) { "$uploadMbps Mbps" } else { 'fail' }
    $pingTxt = if ($pingOk) { "${latencyMs}ms" } else { 'fail' }
    $r.Message = "Net smoke: ping=$pingTxt dl=$dlTxt up=$upTxt"
    $r.Success = ($pingOk -or $downloadOk -or $uploadOk)
}

$script:LocAgentHandlers['GetWindowsUpdateStatus'] = {
    param($r)
    $pendingReboot = $false
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $pendingReboot = $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $pendingReboot = $true }
    $pending = @()
    $lastSuccess = $null
    $comError = $null
    try {
        $wuJob = Start-Job -ScriptBlock {
            $out = @{ Pending = @(); LastHistoryDate = $null; Error = $null }
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $historyCount = $searcher.GetTotalHistoryCount()
                if ($historyCount -gt 0) {
                    $hist = $searcher.QueryHistory(0, 1)
                    if ($hist.Count -gt 0) { $out.LastHistoryDate = $hist.Item(0).Date.ToString("yyyy-MM-dd HH:mm:ss") }
                }
                $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
                $list = @()
                for ($i = 0; $i -lt $result.Updates.Count -and $i -lt 25; $i++) {
                    $u = $result.Updates.Item($i)
                    $list += @{ Title = [string]$u.Title; IsDownloaded = [bool]$u.IsDownloaded; SizeMB = [math]::Round($u.MaxDownloadSize / 1MB, 1) }
                }
                $out.Pending = $list
            }
            catch {
                $out.Error = $_.Exception.Message
            }
            return $out
        }
        if (Wait-Job $wuJob -Timeout 90) {
            $wuOut = Receive-Job $wuJob
            $pending = @($wuOut.Pending)
            $lastSuccess = $wuOut.LastHistoryDate
            if ($wuOut.Error) {
                $comError = [string]$wuOut.Error
                & $r.AddLog "WU search: $comError"
            }
        }
        else {
            Stop-Job $wuJob -ErrorAction SilentlyContinue
            $comError = "WU search timed out after 90s"
            & $r.AddLog $comError
        }
        Remove-Job $wuJob -Force -ErrorAction SilentlyContinue
    }
    catch {
        $comError = $_.Exception.Message
        & $r.AddLog "WU search: $comError"
    }
    $r.Data = @{
        PendingReboot   = $pendingReboot
        LastHistoryDate = $lastSuccess
        PendingUpdates  = @($pending)
        PendingCount    = @($pending).Count
        Note            = $comError
    }
    $r.Message = "Pending updates: $(@($pending).Count)"
    $r.Success = $true
}

$script:LocAgentHandlers['InstallWindowsUpdates'] = {
    param($r)
    & $r.AddLog "Searching pending Windows Updates..."
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
    if ($result.Updates.Count -eq 0) {
        $r.Message = "No pending updates"
        $r.Data = @{ InstalledCount = 0 }
        $r.Success = $true
    }
    else {
        $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        $titles = @()
        $max = [Math]::Min(15, $result.Updates.Count)
        for ($i = 0; $i -lt $max; $i++) {
            $u = $result.Updates.Item($i)
            if ($u.EulaAccepted -eq $false) { $u.AcceptEula() }
            [void]$toInstall.Add($u)
            $titles += [string]$u.Title
            & $r.AddLog "Queued: $($u.Title)"
        }
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $toInstall
        & $r.AddLog ("Downloading {0} update(s)..." -f $toInstall.Count)
        $dlResult = $downloader.Download()
        & $r.AddLog "Download result code: $($dlResult.ResultCode)"
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $toInstall
        & $r.AddLog "Installing..."
        $instResult = $installer.Install()
        $r.ExitCode = [int]$instResult.ResultCode
        $reboot = [bool]$instResult.RebootRequired
        $r.Data = @{
            InstalledCount = $toInstall.Count
            Titles         = @($titles)
            ResultCode     = $r.ExitCode
            RebootRequired = $reboot
        }
        $r.Success = ($r.ExitCode -eq 2 -or $r.ExitCode -eq 3)
        $r.Message = "Installed $($toInstall.Count) update(s); result=$r.ExitCode; reboot=$reboot"
    }
}
