# GetTcpGlobal.ps1
try {
    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("interface", "tcp", "show", "global") -TimeoutSec 5
    $settings = @{}
    foreach ($line in @($r.Output -split "`r?`n")) {
        if ($line -match '^\s*(.+?)\s*:\s*(.+)\s*$') {
            $settings[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return New-ApiResult -Success $true -Message "TCP global settings" -Data ([PSCustomObject]@{
        Success  = ($r.ExitCode -eq 0)
        Settings = $settings
        Raw      = ($r.Output -split "`r?`n" | Select-Object -First 20) -join "`n"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
