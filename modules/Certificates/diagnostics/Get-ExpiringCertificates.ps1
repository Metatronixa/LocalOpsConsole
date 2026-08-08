param([hashtable]$Params = @{})
try {
    $days = 60
    if ($Params.Days) { [void][int]::TryParse([string]$Params.Days, [ref]$days) }
    $cutoff = (Get-Date).AddDays($days)
    $expiring = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.NotAfter -lt $cutoff } |
        Select-Object -First 50 Subject, Thumbprint, NotAfter, Issuer)
    return New-ApiResult -Success $true -Message ("{0} expiring within {1} days" -f $expiring.Count, $days) -Data @{ Available = $true; Days = $days; Certificates = @($expiring) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
