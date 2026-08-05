param([Parameter(Mandatory)][string]$ServiceName)

try {
    Stop-Service -Name $ServiceName -Force -ErrorAction Stop
    $s = Get-Service -Name $ServiceName
    return New-ApiResult -Success $true -Message "Stopped $ServiceName" -Data ([PSCustomObject]@{
        Name   = $s.Name
        Status = [string]$s.Status
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
