try {
    $rows = @()
    $cfgs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop)
    foreach ($cfg in $cfgs) {
        $rows += [PSCustomObject]@{
            Description          = [string]$cfg.Description
            Index                = [int]$cfg.Index
            InterfaceIndex       = [int]$cfg.InterfaceIndex
            WINSPrimaryServer    = if ($cfg.WINSPrimaryServer) { [string]$cfg.WINSPrimaryServer } else { "" }
            WINSSecondaryServer  = if ($cfg.WINSSecondaryServer) { [string]$cfg.WINSSecondaryServer } else { "" }
            TcpipNetbiosOptions  = $cfg.TcpipNetbiosOptions
            NetbiosMode          = Get-LocNetbiosModeLabel -Value $cfg.TcpipNetbiosOptions
            DHCPEnabled          = [bool]$cfg.DHCPEnabled
            IPAddress            = if ($cfg.IPAddress) { (@($cfg.IPAddress) -join ', ') } else { "" }
        }
    }
    return New-ApiResult -Success $true -Message ("{0} adapter(s)" -f $rows.Count) -Data @($rows)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
