param([hashtable]$Params = @{})
$null = $Params
try {
    $stores = @('My','Root','CA')
    $summary = @()
    foreach ($s in $stores) {
        try {
            $certs = @(Get-ChildItem "Cert:\LocalMachine\$s" -ErrorAction SilentlyContinue)
            $summary += [PSCustomObject]@{ Store = $s; Count = $certs.Count }
        } catch {
            $summary += [PSCustomObject]@{ Store = $s; Count = 0; Error = $_.Exception.Message }
        }
    }
    return New-ApiResult -Success $true -Message 'Certificate store health' -Data @{ Available = $true; Stores = @($summary) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
