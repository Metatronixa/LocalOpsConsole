# Services/diagnostics/CriticalMonitor.ps1
# Compare running services against config/services profiles

try {
    $cfgDir = Join-Path (Get-LocRoot) "config\services"
    $profiles = @()
    if (Test-Path $cfgDir) {
        Get-ChildItem $cfgDir -Filter "*.json" | ForEach-Object {
            try { $profiles += (Get-Content $_.FullName -Raw | ConvertFrom-Json) } catch { Write-Debug $_.Exception.Message }
        }
    }

    $results = @()
    foreach ($p in $profiles) {
        $name = [string]$p.service
        if (-not $name) { continue }
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        $status = if ($svc) { [string]$svc.Status } else { "Missing" }
        $startType = if ($svc) { [string]$svc.StartType } else { "Unknown" }
        $ok = $true
        $issues = @()
        if (-not $svc) {
            $ok = $false
            $issues += "Service not found"
        }
        else {
            if ($p.mustBeRunning -and $status -ne "Running") {
                $ok = $false
                $issues += "Expected Running, is $status"
            }
            if ($p.startup -and $startType -ne $p.startup -and $p.startup -ne "Ignore") {
                $issues += "Startup is $startType (profile wants $($p.startup))"
                if ($p.critical) { $ok = $false }
            }
        }
        $results += [PSCustomObject]@{
            Service     = $name
            Status      = $status
            StartType   = $startType
            Critical    = [bool]$p.critical
            Healthy     = $ok
            Issues      = $issues
            Notify      = [bool]$p.notify
            Profile     = $p
        }
    }

    $unhealthy = @($results | Where-Object { -not $_.Healthy })
    New-ApiResult -Success $true -Message ("Critical service monitor: {0} issue(s)" -f $unhealthy.Count) -Data @{
        Items     = @($results)
        Unhealthy = @($unhealthy)
        Healthy   = ($unhealthy.Count -eq 0)
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
