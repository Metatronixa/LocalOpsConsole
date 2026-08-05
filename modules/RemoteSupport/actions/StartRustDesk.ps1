try {
    $exe = Get-RustDeskExePath
    $svc = Get-RustDeskServiceInfo
    $started = @()

    if ($svc.Found -and $svc.Status -ne 'Running') {
        Start-Service -Name $svc.Name -ErrorAction Stop
        $started += "Service $($svc.Name)"
    }

    if (-not (Test-RustDeskProcessRunning)) {
        if (-not $exe) {
            return New-ApiResult -Success $false -Message "RustDesk is not installed."
        }
        Start-Process -FilePath $exe -ErrorAction Stop
        $started += 'Process'
    }

    Start-Sleep -Milliseconds 800
    $status = Get-RustDeskStatusSnapshot
    $msg = if ($started.Count -gt 0) {
        "Started RustDesk ({0})" -f ($started -join ', ')
    }
    else {
        'RustDesk is already running'
    }
    return New-ApiResult -Success $true -Message $msg -Data $status
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
