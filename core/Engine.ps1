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
        "LicenseManager.ps1",
        "Logger.ps1",
        "Cache.ps1",
        "Console.ps1",
        "IntegrityManager.ps1",
        "PermissionManager.ps1",
        "ModuleLoader.ps1",
        "ModuleLoaderInvoke.ps1",
        "SecurityManager.ps1",
        "TaskRunner.ps1",
        "TaskRunnerUpdate.ps1",
        "TaskRunnerExtras.ps1",
        "Updater.ps1",
        "UpdaterApply.ps1",
        "FleetStore.ps1",
        "FleetStoreInit.ps1",
        "FleetAuth.ps1",
        "Fleet.ps1",
        "FleetAgents.ps1",
        "FleetAgentOps.ps1",
        "FleetDeviceTypes.ps1",
        "FleetTopology.ps1",
        "FleetPackages.ps1",
        "FleetPackageContent.ps1",
        "FleetCommands.ps1",
        "FleetCommandCancel.ps1",
        "FleetCommandClaim.ps1",
        "FleetCommandQuery.ps1",
        "FleetAlerts.ps1",
        "FleetEnrollToken.ps1",
        "FleetScripts.ps1",
        "ScriptBlockDecoder.ps1",
        "ThreatSeverity.ps1",
        "ThreatTelemetryStore.ps1",
        "ThreatTelemetryService.ps1",
        "ThreatKnowledgeEngine.ps1",
        "RiskEngine.ps1",
        "EventStore.ps1",
        "EventStoreData.ps1",
        "Timeline.ps1",
        "SeverityEngine.ps1",
        "RuleEngine.ps1",
        "CorrelationEngine.ps1",
        "IncidentManager.ps1",
        "NotificationGate.ps1",
        "NotificationManager.ps1",
        "WatchManager.ps1",
        "HealthMonitor.ps1",
        "HealthMonitorScore.ps1",
        "SecurityScore.ps1",
        "AutomationHandlers.ps1",
        "AutomationPlaybookPrefs.ps1",
        "AutomationPlaybookRules.ps1",
        "AutomationRunNow.ps1",
        "AutomationEngine.ps1",
        "KnowledgeService.ps1",
        "PlaybookService.ps1",
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
