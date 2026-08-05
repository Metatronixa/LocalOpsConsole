param([Parameter(Mandatory)][string]$ServiceName)

try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    $s = Get-Service -Name $ServiceName
    return New-ApiResult -Success $true -Message "Started $ServiceName" -Data ([PSCustomObject]@{
        Name   = $s.Name
        Status = [string]$s.Status
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
