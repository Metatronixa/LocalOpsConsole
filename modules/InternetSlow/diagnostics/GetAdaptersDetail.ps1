# GetAdaptersDetail.ps1
try {
    $rows = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            Name           = $_.Name
            Status         = [string]$_.Status
            LinkSpeed      = [string]$_.LinkSpeed
            MacAddress     = [string]$_.MacAddress
            Enabled        = [bool]($_.AdminStatus -eq 'Up')
            MediaConnected = [bool]$_.MediaConnected
            InterfaceDescription = [string]$_.InterfaceDescription
            Virtual        = [bool]$_.Virtual
        }
    })
    return New-ApiResult -Success $true -Message ("{0} adapter(s)" -f $rows.Count) -Data @($rows)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
