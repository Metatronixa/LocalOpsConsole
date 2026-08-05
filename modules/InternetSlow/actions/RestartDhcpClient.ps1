# RestartDhcpClient.ps1
try {
    Restart-Service -Name Dhcp -Force -ErrorAction Stop
    return New-ApiResult -Success $true -Message "DHCP Client service restarted"
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
