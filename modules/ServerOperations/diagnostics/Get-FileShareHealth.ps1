param([hashtable]$Params = @{})
$null = $Params
try {
    $shares = @(Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '\$$' } | Select-Object -First 50 Name, Path, Description)
    return New-ApiResult -Success $true -Message ("{0} share(s)" -f $shares.Count) -Data @{ Available = $true; Shares = @($shares) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
