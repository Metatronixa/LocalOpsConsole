param([Parameter(Mandatory)][string]$InstanceId)
try {
    Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Disabled device" -Data ([PSCustomObject]@{ InstanceId = $InstanceId })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
