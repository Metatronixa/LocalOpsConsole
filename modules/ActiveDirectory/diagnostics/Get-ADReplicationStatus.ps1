param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Import-LocADModule
    if (-not $st.Available) {
        return New-ApiResult -Success $true -Message 'AD not available' -Data @{ Available = $false; Status = $st }
    }
    $rep = @()
    try {
        $rep = @(Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction SilentlyContinue |
            Select-Object -First 30 Server, Partner, LastReplicationSuccess, LastReplicationResult)
    } catch {
        $rep = @([PSCustomObject]@{ Note = 'Replication metadata requires DC context'; Error = $_.Exception.Message })
    }
    return New-ApiResult -Success $true -Message 'AD replication status' -Data @{ Available = $true; Partners = @($rep) }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
