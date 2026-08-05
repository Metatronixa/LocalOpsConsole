try {
    $svc = Get-RustDeskServiceInfo
    if (-not $svc.Found) {
        return New-ApiResult -Success $false -Message "No RustDesk Windows service found."
    }

    Restart-Service -Name $svc.Name -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 800
    $status = Get-RustDeskStatusSnapshot
    return New-ApiResult -Success $true -Message "Restarted service $($svc.Name)" -Data $status
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
