try {
    $targets = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match "WAN Miniport"
    }
    $reset = @()
    foreach ($a in @($targets)) {
        try {
            Disable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 500
            Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
            $reset += $a.Name
        }
        catch { Write-Debug $_.Exception.Message }
    }
    return New-ApiResult -Success $true -Message ("Reset {0} WAN Miniport adapter(s)" -f $reset.Count) -Data ([PSCustomObject]@{ Reset = @($reset) })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
