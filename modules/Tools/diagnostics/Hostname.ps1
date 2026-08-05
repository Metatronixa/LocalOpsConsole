return New-ApiResult -Success $true -Message "hostname" -Data ([PSCustomObject]@{
    Output   = $env:COMPUTERNAME
    Hostname = $env:COMPUTERNAME
    ExitCode = 0
})
