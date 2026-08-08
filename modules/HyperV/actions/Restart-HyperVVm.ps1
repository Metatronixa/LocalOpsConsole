param([hashtable]$Params = @{})
try {
    $st = Test-LocHyperVAvailable
    if (-not $st.Available) { return New-ApiResult -Success $false -Message 'Hyper-V not present' -StatusCode 503 }
    $name = if ($Params.Name) { [string]$Params.Name } elseif ($Params.VmName) { [string]$Params.VmName } else { '' }
    if ([string]::IsNullOrWhiteSpace($name)) { return New-ApiResult -Success $false -Message 'Name required' -StatusCode 400 }
    Import-Module Hyper-V -ErrorAction Stop | Out-Null
    Restart-VM -Name $name -Force -ErrorAction Stop
    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'HyperV' -Category 'Action' -Summary "Restarted VM $name" -Data @{ Name = $name; RiskLevel = 'HIGH' }
    }
    return New-ApiResult -Success $true -Message "Restarted VM $name" -Data @{ Name = $name }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
