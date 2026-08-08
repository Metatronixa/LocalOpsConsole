param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocGpoAvailable
    if (-not $st.Available) { return New-ApiResult -Success $true -Message 'Host not domain-joined' -Data @{ Available = $false; Status = $st } }
    $gpos = @()
    if ($st.HasModule) {
        Import-Module GroupPolicy -ErrorAction SilentlyContinue | Out-Null
        $gpos = @(Get-GPO -All -ErrorAction SilentlyContinue | Select-Object -First 40 DisplayName, Id, ModificationTime, GpoStatus)
    }
    return New-ApiResult -Success $true -Message 'GPO health' -Data @{ Available = $true; GpoCount = $gpos.Count; Gpos = @($gpos) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
