# GetNetworkEvents.ps1
try {
    $providers = @(
        'Microsoft-Windows-Dhcp-Client',
        'Microsoft-Windows-DNS-Client',
        'Microsoft-Windows-TCPIP'
    )
    $events = [System.Collections.ArrayList]::new()
    foreach ($prov in $providers) {
        try {
            $batch = Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                ProviderName = $prov
            } -MaxEvents 5 -ErrorAction SilentlyContinue
            foreach ($e in @($batch)) {
                [void]$events.Add([PSCustomObject]@{
                    TimeCreated = $e.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    Provider    = $e.ProviderName
                    Id          = $e.Id
                    Level       = [string]$e.LevelDisplayName
                    Message     = ($e.Message -split "`n" | Select-Object -First 2) -join " "
                })
            }
        }
        catch { Write-Debug $_.Exception.Message }
    }

    $sorted = @($events | Sort-Object { $_.TimeCreated } -Descending | Select-Object -First 15)
    return New-ApiResult -Success $true -Message ("{0} recent network event(s)" -f $sorted.Count) -Data @($sorted)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
