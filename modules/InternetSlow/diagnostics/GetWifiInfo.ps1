# GetWifiInfo.ps1
try {
    $wireless = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and ($_.MediaType -match '802\.11|Native80211|Wireless' -or $_.InterfaceDescription -match 'Wi-?Fi|Wireless')
    } | Select-Object -First 1

    if (-not $wireless) {
        return New-ApiResult -Success $true -Message "No Wi-Fi adapter active" -Data ([PSCustomObject]@{
            HasWifi = $false
        })
    }

    $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("wlan", "show", "interfaces") -TimeoutSec 5
    $lines = @($r.Output -split "`r?`n")
    $parsed = @{}
    foreach ($line in $lines) {
        if ($line -match '^\s*(.+?)\s*:\s*(.+)\s*$') {
            $parsed[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    return New-ApiResult -Success $true -Message "Wi-Fi interface" -Data ([PSCustomObject]@{
        HasWifi   = $true
        Adapter   = $wireless.Name
        Fields    = $parsed
        Snippet   = ($lines | Select-Object -First 25) -join "`n"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
