# EnableAdapter.ps1
param([string]$InterfaceAlias = "")

try {
    if ([string]::IsNullOrWhiteSpace($InterfaceAlias)) {
        $na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.AdminStatus -eq 'Down' -and -not $_.Virtual } | Select-Object -First 1
        $InterfaceAlias = if ($na) { $na.Name } else { (Get-NetAdapter | Select-Object -First 1).Name }
    }
    if (-not $InterfaceAlias) { return New-ApiResult -Success $false -Message "No adapter specified" }
    Enable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Adapter '$InterfaceAlias' enabled" -Data ([PSCustomObject]@{
        InterfaceAlias = $InterfaceAlias
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
