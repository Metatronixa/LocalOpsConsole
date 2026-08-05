param([Parameter(Mandatory)][string]$ServiceName)

try {
    Restart-Service -Name $ServiceName -Force -ErrorAction Stop
    $s = Get-Service -Name $ServiceName
    return New-ApiResult -Success $true -Message "Restarted $ServiceName" -Data ([PSCustomObject]@{
        Name   = $s.Name
        Status = [string]$s.Status
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
