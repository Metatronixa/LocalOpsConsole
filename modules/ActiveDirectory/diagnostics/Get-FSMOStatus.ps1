param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Import-LocADModule
    if (-not $st.Available) {
        return New-ApiResult -Success $true -Message 'AD not available' -Data @{ Available = $false; Status = $st }
    }
    $domain = Get-ADDomain -ErrorAction Stop
    $forest = Get-ADForest -ErrorAction Stop
    return New-ApiResult -Success $true -Message 'FSMO status' -Data @{
        Available = $true
        PDCEmulator = $domain.PDCEmulator
        RIDMaster = $domain.RIDMaster
        InfrastructureMaster = $domain.InfrastructureMaster
        SchemaMaster = $forest.SchemaMaster
        DomainNamingMaster = $forest.DomainNamingMaster
    }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
