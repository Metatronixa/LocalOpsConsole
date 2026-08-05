try {
    $svc = Get-Service -Name Spooler -ErrorAction Stop
    $depOn = @($svc.ServicesDependedOn | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status; StartType = [string]$_.StartType }
    })
    $depBy = @($svc.DependentServices | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status; StartType = [string]$_.StartType }
    })
    $recovery = Get-LocSpoolerRecoveryInfo

    return New-ApiResult -Success $true -Message ("Spooler is {0}" -f $svc.Status) -Data ([PSCustomObject]@{
        Name              = [string]$svc.Name
        DisplayName       = [string]$svc.DisplayName
        Status            = [string]$svc.Status
        StartType         = [string]$svc.StartType
        CanStop           = [bool]$svc.CanStop
        ServicesDependedOn = $depOn
        DependentServices  = $depBy
        Recovery          = $recovery
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
