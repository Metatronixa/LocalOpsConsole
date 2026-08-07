# tools/smoke-api.ps1 - Local API smoke test (server must be running)
[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:8787/api/v1"
)

$ErrorActionPreference = "Continue"
$script:pass = 0
$script:fail = 0

function Test-Api {
    param(
        [string]$Name,
        [string]$Method = "GET",
        [string]$Path,
        [string]$Body = $null,
        [int[]]$ExpectStatus = @(200),
        [scriptblock]$Extra = $null
    )
    $uri = "$BaseUrl/$Path"
    try {
        $params = @{
            Uri             = $uri
            Method          = $Method
            UseBasicParsing = $true
            TimeoutSec      = 30
        }
        if ($Body) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }
        $r = Invoke-WebRequest @params
        $code = [int]$r.StatusCode
        $json = $null
        try { $json = $r.Content | ConvertFrom-Json } catch { }
        $ok = $ExpectStatus -contains $code
        if ($ok -and ($ExpectStatus -contains 200) -and $json -and ($json.PSObject.Properties.Name -contains "Success")) {
            $ok = [bool]$json.Success
        }
        if ($ok -and $Extra) {
            $ok = [bool](& $Extra $json $r)
        }
        if ($ok) {
            Write-Host "PASS  $Name ($code)" -ForegroundColor Green
            $script:pass++
        }
        else {
            $msg = if ($json) { [string]$json.Message } else { [string]$r.Content }
            Write-Host "FAIL  $Name ($code) $msg" -ForegroundColor Red
            $script:fail++
        }
    }
    catch {
        $code = 0
        if ($_.Exception.Response) {
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        }
        if (($ExpectStatus -contains $code) -and ($code -ne 0)) {
            Write-Host "PASS  $Name ($code expected)" -ForegroundColor Green
            $script:pass++
        }
        else {
            Write-Host "FAIL  $Name - $($_.Exception.Message)" -ForegroundColor Red
            $script:fail++
        }
    }
}

Write-Host "Smoke testing $BaseUrl" -ForegroundColor Cyan

Test-Api -Name "health" -Path "health"
Test-Api -Name "modules" -Path "modules" -Extra {
    param($j)
    @($j.Data).Count -ge 1
}
Test-Api -Name "settings GET" -Path "settings"
Test-Api -Name "settings POST" -Method "POST" -Path "settings" -Body '{"eventIntel":{"notifyLevel":"Warning"}}'
Test-Api -Name "settings PUT -> 405" -Method "PUT" -Path "settings" -ExpectStatus @(405)
Test-Api -Name "telemetry" -Path "telemetry"
Test-Api -Name "fleet agents" -Path "fleet/agents"
Test-Api -Name "fleet enroll-token" -Path "fleet/enroll-token" -Extra {
    param($j)
    $u = [string]$j.Data.SuggestedUrl
    -not [string]::IsNullOrWhiteSpace($u)
}
Test-Api -Name "graphics" -Path "graphics/diagnostics/GetAdapters"
Test-Api -Name "syncme" -Path "syncme/diagnostics/GetStatus"
Test-Api -Name "startup" -Path "startup/diagnostics/GetStartupApps"
Test-Api -Name "devices" -Path "devices/diagnostics/GetProblemDevices"
Test-Api -Name "power" -Path "power/diagnostics/GetPowerPlan"
Test-Api -Name "users" -Path "users/diagnostics/GetLocalUsers"
Test-Api -Name "configuration catalog" -Path "configuration/diagnostics/GetCatalog"
Test-Api -Name "health-score" -Path "health-score"
Test-Api -Name "security-score" -Path "security-score"
Test-Api -Name "incidents" -Path "incidents?status=active"
Test-Api -Name "alerts" -Path "alerts"
Test-Api -Name "automation status" -Path "automation/status" -Extra {
    param($j)
    $d = $j.Data
    if (-not $d) { return $false }
    $handlers = @($d.Handlers)
    $rules = @($d.Rules)
    $needHandlers = @(
        "clear-print-queue",
        "network-soft-repair",
        "restart-update-stack",
        "capture-process-snapshot"
    )
    foreach ($h in $needHandlers) {
        if ($handlers -notcontains $h) { return $false }
    }
    if ($rules.Count -lt 10) { return $false }
    $ids = @($rules | ForEach-Object { [string]$_.RuleId })
    $needRules = @(
        "spooler-crash",
        "low-disk",
        "service-down",
        "printer-offline",
        "network-down",
        "update-failed",
        "eventlog-health",
        "defender-disabled",
        "firewall-disabled",
        "unexpected-reboot",
        "high-cpu"
    )
    foreach ($id in $needRules) {
        if ($ids -notcontains $id) { return $false }
    }
    $sample = $rules | Where-Object { $_.RuleId -eq "high-cpu" } | Select-Object -First 1
    if (-not $sample) { return $false }
    if (-not $sample.PSObject.Properties['Scope']) { return $false }
    if (-not $sample.PSObject.Properties['SupportsFleet']) { return $false }
    $true
}

Write-Host ""
$color = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host ("Result: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $color
if ($script:fail -gt 0) { exit 1 }
exit 0
