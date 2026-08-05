# Privilege / elevation diagnostic
return New-ApiResult -Success $true -Message "Privilege status" -Data ([PSCustomObject]@{
    IsAdmin      = Test-IsAdmin
    UserName     = $env:USERNAME
    UserDomain   = $env:USERDOMAIN
    ComputerName = $env:COMPUTERNAME
})
