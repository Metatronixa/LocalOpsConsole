param([hashtable]$Params = @{})
$null = $Params
try {
    $st = Test-LocGpoAvailable
    $out = (gpresult /R 2>&1 | Out-String)
    $len = [Math]::Min(8000, $out.Length)
    return New-ApiResult -Success $true -Message 'gpresult summary' -Data @{ Available = [bool]$st.Available; Text = $out.Substring(0, $len) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
