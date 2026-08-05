try {
    $svc = Get-RustDeskServiceInfo
    $stopped = @()

    Get-Process -Name 'rustdesk' -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $stopped += 'Process'
    }

    if ($svc.Found -and $svc.Status -eq 'Running') {
        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
        $stopped += "Service $($svc.Name)"
    }

    Start-Sleep -Milliseconds 500
    $status = Get-RustDeskStatusSnapshot
    $msg = if ($stopped.Count -gt 0) {
        "Stopped RustDesk ({0})" -f ($stopped -join ', ')
    }
    else {
        'RustDesk was not running'
    }
    return New-ApiResult -Success $true -Message $msg -Data $status
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
