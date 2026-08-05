try {
    $killed = @()
    Get-Process -Name spoolsv -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        $killed += $_.Id
    }

    Start-Sleep -Milliseconds 500
    $svc = Get-Service Spooler -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Start-Service Spooler -ErrorAction SilentlyContinue
    }
    $svc = Get-Service Spooler -ErrorAction SilentlyContinue

    return New-ApiResult -Success $true -Message ("Killed {0} spooler process(es)" -f $killed.Count) -Data ([PSCustomObject]@{
        ProcessIds    = $killed
        SpoolerStatus = if ($svc) { [string]$svc.Status } else { "Unknown" }
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
