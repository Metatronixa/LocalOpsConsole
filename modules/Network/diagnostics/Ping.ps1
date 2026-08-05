param(
    [string]$Target = "8.8.8.8",
    [int]$Count = 1
)

try {
    $results = Test-Connection -ComputerName $Target -Count $Count -ErrorAction Stop
    $rows = @($results | ForEach-Object {
        [PSCustomObject]@{
            Address    = $_.Address
            ResponseMs = $_.ResponseTime
            Status     = "Success"
        }
    })
    $avg = if ($rows.Count) { [math]::Round(($rows | Measure-Object ResponseMs -Average).Average, 1) } else { 0 }
    return New-ApiResult -Success $true -Message "Ping $Target OK (avg ${avg}ms)" -Data ([PSCustomObject]@{
        Target  = $Target
        Average = $avg
        Results = $rows
    })
}
catch {
    return New-ApiResult -Success $false -Message "Ping failed: $($_.Exception.Message)" -Data ([PSCustomObject]@{ Target = $Target })
}
