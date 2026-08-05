# RestartDnsClient.ps1
try {
    Restart-Service -Name Dnscache -Force -ErrorAction Stop
    return New-ApiResult -Success $true -Message "DNS Client (Dnscache) service restarted"
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
