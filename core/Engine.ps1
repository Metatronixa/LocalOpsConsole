# core/Engine.ps1 - Ordered core bootstrap facade
# IMPORTANT: Callers must dot-source each path at *script* scope (not inside a
# function), or helpers vanish when that function returns.

function Get-LocCoreEngineFiles {
    param([Parameter(Mandatory)][string]$RootPath)

    $core = Join-Path $RootPath "core"
    $ordered = @(
        "Response.ps1",
        "Security.ps1",
        "Settings.ps1",
        "Logger.ps1",
        "Cache.ps1",
        "Console.ps1",
        "IntegrityManager.ps1",
        "PermissionManager.ps1",
        "ModuleLoader.ps1",
        "SecurityManager.ps1",
        "TaskRunner.ps1",
        "Updater.ps1",
        "FleetStore.ps1",
        "FleetAuth.ps1",
        "Fleet.ps1",
        "EventStore.ps1",
        "Timeline.ps1",
        "SeverityEngine.ps1",
        "RuleEngine.ps1",
        "CorrelationEngine.ps1",
        "IncidentManager.ps1",
        "NotificationManager.ps1",
        "WatchManager.ps1",
        "HealthMonitor.ps1",
        "SecurityScore.ps1",
        "AutomationEngine.ps1",
        "EventEngine.ps1"
    )

    # Emit one path per pipeline object (avoids array-stringify when dot-sourcing)
    foreach ($name in $ordered) {
        $path = Join-Path $core $name
        if (Test-Path -LiteralPath $path) {
            $path
        }
        else {
            Write-Warning "Core script missing: $name"
        }
    }
}
