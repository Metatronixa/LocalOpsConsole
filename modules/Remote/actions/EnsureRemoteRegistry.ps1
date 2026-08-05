param(
    [Parameter(Mandatory)]
    [string]$ComputerName
)

try {
    $svc = Get-Service -ComputerName $ComputerName -Name RemoteRegistry -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
        Set-Service -ComputerName $ComputerName -Name RemoteRegistry -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -InputObject (Get-Service -ComputerName $ComputerName -Name RemoteRegistry) -ErrorAction Stop
        $svc = Get-Service -ComputerName $ComputerName -Name RemoteRegistry
    }
    return New-ApiResult -Success ($svc.Status -eq 'Running') -Message "Remote Registry on $ComputerName is $($svc.Status)" -Data ([PSCustomObject]@{
        ComputerName = $ComputerName
        Status       = [string]$svc.Status
        StartType    = [string]$svc.StartType
    })
}
catch {
    # Fallback sc.exe
    try {
        $out = sc.exe "\\$ComputerName" start RemoteRegistry 2>&1 | Out-String
        return New-ApiResult -Success $true -Message "Requested start of Remote Registry on $ComputerName" -Data ([PSCustomObject]@{
            ComputerName = $ComputerName
            Output       = $out.Trim()
        })
    }
    catch {
        return New-ApiResult -Success $false -Message "Could not start Remote Registry on ${ComputerName}: $($_.Exception.Message)"
    }
}
