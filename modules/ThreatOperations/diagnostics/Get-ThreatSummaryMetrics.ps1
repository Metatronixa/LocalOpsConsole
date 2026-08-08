param([hashtable]$Params = @{})
$null = $Params
. (Join-Path $PSScriptRoot '..\lib\ThreatRuleDefinitions.ps1')

try {
    $hours = 24
    if ($Params.Hours) { [void][int]::TryParse([string]$Params.Hours, [ref]$hours) }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-1 * $hours)
    $rows = @(Get-LocThreatEventRecords -Max 50000)
    $inWindow = @()
    foreach ($r in $rows) {
        try {
            $ts = [datetime]::Parse([string]$r.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if ($ts -ge $cutoff) { $inWindow += $r }
        }
        catch { Write-Debug $_.Exception.Message }
    }
    $critical = @($inWindow | Where-Object { [string]$_.severity -eq 'CRITICAL' }).Count
    $high = @($inWindow | Where-Object { [string]$_.severity -eq 'HIGH' }).Count
    $medLow = @($inWindow | Where-Object { [string]$_.severity -in @('MEDIUM', 'LOW') }).Count
    $info = @($inWindow | Where-Object { [string]$_.severity -eq 'INFO' }).Count
    return New-ApiResult -Success $true -Message 'Threat summary metrics' -Data @{
        WindowHours = $hours
        Critical    = $critical
        High        = $high
        MediumLow   = $medLow
        Info        = $info
        Total       = $inWindow.Count
    }
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
