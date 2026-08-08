# RegisterDns.ps1 — ipconfig /registerdns
try {
    $out = ipconfig /registerdns 2>&1 | Out-String
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    return New-ApiResult -Success $true -Message "DNS registration completed" -Data ([PSCustomObject]@{ Output = $out.Trim() })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
