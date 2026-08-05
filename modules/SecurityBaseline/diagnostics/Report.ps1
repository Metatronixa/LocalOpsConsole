# modules/SecurityBaseline/diagnostics/Report.ps1
# Thin wrapper — same audit payload shaped for reporting/export

$auditPath = Join-Path $PSScriptRoot "Audit.ps1"
$raw = @(. $auditPath)
$result = $raw | Where-Object { $null -ne $_ -and ($_.PSObject.Properties.Name -contains 'Success') } | Select-Object -Last 1
if (-not $result) {
    return New-ApiResult -Success $false -Message "Baseline audit failed" -StatusCode 500
}
if (-not $result.Success) { return $result }

$d = $result.Data
$report = [PSCustomObject]@{
    Title           = "LocalOpsConsole Security Baseline Report"
    GeneratedAt     = $d.GeneratedAt
    Score           = $d.Score
    RiskRating      = $d.RiskRating
    Compliance      = $d.Compliance
    Summary         = "Score $($d.Score)% · Risk $($d.RiskRating) · $($d.Compliance.Passed)/$($d.Compliance.Total) controls passing"
    Checks          = $d.Checks
    Recommendations = $d.Recommendations
}

New-ApiResult -Success $true -Message "Security baseline report" -Data $report
