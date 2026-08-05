# Flush DNS resolver cache
try {
    Clear-DnsClientCache -ErrorAction Stop
    $out = ipconfig /flushdns 2>&1 | Out-String
    return New-ApiResult -Success $true -Message "DNS cache flushed" -Data ([PSCustomObject]@{ Output = $out.Trim() })
}
catch {
    try {
        $out = ipconfig /flushdns 2>&1 | Out-String
        return New-ApiResult -Success $true -Message "DNS cache flushed" -Data ([PSCustomObject]@{ Output = $out.Trim() })
    }
    catch {
        return New-ApiResult -Success $false -Message $_.Exception.Message
    }
}
