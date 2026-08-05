try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name            = [string]$_.Name
            Enabled         = [bool]$_.Enabled
            DefaultInbound  = [string]$_.DefaultInboundAction
            DefaultOutbound = [string]$_.DefaultOutboundAction
            LogAllowed      = [bool]$_.LogAllowed
            LogBlocked      = [bool]$_.LogBlocked
        }
    }
    return New-ApiResult -Success $true -Message "Firewall profiles" -Data @($profiles)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
