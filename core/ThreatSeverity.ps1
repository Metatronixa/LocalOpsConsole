# ThreatSeverity.ps1 - Environment-aware severity elevation matrix
function Get-LocThreatAllowedProfiles {
    return @(
        'DomainController'
        'ActiveDirectoryMember'
        'EntraCloudJoined'
        'StandaloneWorkgroup'
    )
}

function Get-LocThreatAllowedEventIds {
    return @(1102, 4104, 4624, 4625, 4688, 4697, 4769, 7045)
}

function Resolve-LocThreatSeverity {
    param(
        [Parameter(Mandatory)][int]$EventId,
        [Parameter(Mandatory)][string]$EnvironmentProfile,
        [string]$BaseSeverity = 'INFO',
        [string]$ProcessName = '',
        [string]$ServiceName = '',
        [bool]$HighRiskScript = $false,
        [int]$FailedLogonBurst = 0
    )

    $sev = if ($BaseSeverity) { $BaseSeverity.ToUpperInvariant() } else { 'INFO' }
    $rank = @{ INFO = 0; LOW = 1; MEDIUM = 2; HIGH = 3; CRITICAL = 4 }
    $raise = {
        param($cur, $want)
        if (-not $rank.ContainsKey($cur)) { $cur = 'INFO' }
        if (-not $rank.ContainsKey($want)) { return $cur }
        if ($rank[$want] -gt $rank[$cur]) { return $want }
        return $cur
    }

    $isDc = ($EnvironmentProfile -eq 'DomainController')
    switch ($EventId) {
        1102 { $sev = & $raise $sev $(if ($isDc) { 'CRITICAL' } else { 'HIGH' }) }
        4104 {
            if ($HighRiskScript) {
                $sev = & $raise $sev $(if ($isDc) { 'CRITICAL' } else { 'HIGH' })
            }
            else {
                $sev = & $raise $sev $(if ($isDc) { 'HIGH' } else { 'MEDIUM' })
            }
        }
        4625 {
            if ($FailedLogonBurst -ge 5) {
                $sev = & $raise $sev $(if ($isDc) { 'HIGH' } else { 'MEDIUM' })
            }
            elseif ($isDc) { $sev = & $raise $sev 'HIGH' }
        }
        4688 {
            if ($ProcessName -match '(?i)powershell(\.exe)?.*-enc') {
                $sev = & $raise $sev $(if ($isDc) { 'MEDIUM' } else { 'MEDIUM' })
            }
        }
        { $_ -in 4697, 7045 } {
            if ($ServiceName -match '(?i)\\Temp\\|\\AppData\\') {
                $sev = & $raise $sev $(if ($isDc) { 'HIGH' } else { 'HIGH' })
            }
            elseif ($isDc) { $sev = & $raise $sev 'HIGH' }
        }
        4769 {
            # RC4 ticket encryption 0x17 often surfaces in message/process context
            if ($ProcessName -match '(?i)0x17|rc4' -or $ServiceName -match '(?i)0x17') {
                $sev = & $raise $sev $(if ($isDc) { 'CRITICAL' } else { 'HIGH' })
            }
            elseif ($isDc) { $sev = & $raise $sev 'CRITICAL' }
        }
    }
    return $sev
}
