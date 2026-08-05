param([Parameter(Mandatory)][string]$ConnectionName)
try {
    Disconnect-VpnConnection -Name $ConnectionName -Force -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Disconnected $ConnectionName" -Data ([PSCustomObject]@{ Name = $ConnectionName })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
