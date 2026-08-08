param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocHyperVAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'Hyper-V not present' -Data @{ Available = $false } }
    Import-Module Hyper-V -ErrorAction Stop | Out-Null
    $vms = @(Get-VM -ErrorAction Stop | Select-Object Name, State, Generation, Version, Uptime)
    return New-ApiResult -Success $true -Message ("{0} VM(s)" -f $vms.Count) -Data @{ Available = $true; Vms = @($vms) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
