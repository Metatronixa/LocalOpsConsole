# GetWinsockInfo.ps1
try {
    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("winsock", "show", "catalog") -TimeoutSec 5
    $lines = @($r.Output -split "`r?`n")
    $lspCount = @($lines | Where-Object { $_ -match '^\s*\d+\s+' }).Count
    $snippet = ($lines | Select-Object -First 15) -join "`n"

    return New-ApiResult -Success $true -Message "Winsock catalog" -Data ([PSCustomObject]@{
        Success   = ($r.ExitCode -eq 0)
        LspCount  = $lspCount
        Snippet   = $snippet
        ExitCode  = $r.ExitCode
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
