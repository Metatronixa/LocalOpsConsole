# OpenHostsFile.ps1 — returns path for UI
try {
    $path = $env:SystemRoot + "\System32\drivers\etc\hosts"
    return New-ApiResult -Success $true -Message "Hosts file path" -Data ([PSCustomObject]@{
        Path   = $path
        Exists = (Test-Path -LiteralPath $path)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
