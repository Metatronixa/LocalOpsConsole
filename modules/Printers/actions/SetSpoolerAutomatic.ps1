try {
    Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop
    $svc = Get-Service Spooler -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Spooler startup set to Automatic" -Data ([PSCustomObject]@{
        StartType = [string]$svc.StartType
        Status    = [string]$svc.Status
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
