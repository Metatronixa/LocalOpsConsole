param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocHyperVAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'Hyper-V not present' -Data @{ Available = $false; Status = $st } }
    Import-Module Hyper-V -ErrorAction SilentlyContinue | Out-Null
    $vms = @(Get-VM -ErrorAction SilentlyContinue | Select-Object Name, State, CPUUsage, MemoryAssigned)
    return New-ApiResult -Success $true -Message 'Hyper-V host health' -Data @{ Available = $true; VmCount = $vms.Count; Vms = @($vms | Select-Object -First 50) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
