param([Parameter(Mandatory)][string]$InstanceId)
try {
    Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Enabled device" -Data ([PSCustomObject]@{ InstanceId = $InstanceId })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
