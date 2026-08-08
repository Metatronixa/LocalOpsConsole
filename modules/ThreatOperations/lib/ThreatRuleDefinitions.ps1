# ThreatRuleDefinitions.ps1 - Shared constants for Threat Operations module
function Get-LocThreatModuleSeverities {
    return @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')
}

function Get-LocThreatModuleEventIds {
    return @(1102, 4104, 4624, 4625, 4688, 4697, 4769, 7045)
}
