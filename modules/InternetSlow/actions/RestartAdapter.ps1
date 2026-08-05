# RestartAdapter.ps1
param([string]$InterfaceAlias = "")

try {
    if ([string]::IsNullOrWhiteSpace($InterfaceAlias)) {
        $a = Get-LocActiveAdapterInfo
        $InterfaceAlias = if ($a) { $a.Name } else { (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1).Name }
    }
    if (-not $InterfaceAlias) { return New-ApiResult -Success $false -Message "No adapter specified" }
    Disable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 2
    Enable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Adapter '$InterfaceAlias' restarted" -Data ([PSCustomObject]@{
        InterfaceAlias = $InterfaceAlias
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
