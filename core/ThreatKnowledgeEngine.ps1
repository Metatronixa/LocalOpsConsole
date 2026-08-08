# ThreatKnowledgeEngine.ps1 - Event-to-playbook mapping helpers
function Get-LocThreatPlaybookHints {
    param(
        [Parameter(Mandatory)][int]$EventId,
        [string[]]$KeywordHits = @()
    )
    $hints = New-Object System.Collections.Generic.List[object]
    switch ($EventId) {
        1102 {
            $hints.Add([PSCustomObject]@{ Id = 'audit-log-cleared'; Title = 'Investigate audit log cleared'; Severity = 'CRITICAL' }) | Out-Null
        }
        4104 {
            $hints.Add([PSCustomObject]@{ Id = 'ps-scriptblock-review'; Title = 'Review PowerShell ScriptBlock'; Severity = 'HIGH' }) | Out-Null
            if ($KeywordHits -contains 'Mimikatz' -or $KeywordHits -contains 'AMSI bypass') {
                $hints.Add([PSCustomObject]@{ Id = 'credential-theft-response'; Title = 'Credential theft response'; Severity = 'CRITICAL' }) | Out-Null
            }
        }
        4625 {
            $hints.Add([PSCustomObject]@{ Id = 'brute-force-lockout'; Title = 'Failed logon / brute-force review'; Severity = 'HIGH' }) | Out-Null
        }
        4688 {
            $hints.Add([PSCustomObject]@{ Id = 'suspicious-process'; Title = 'Review process creation'; Severity = 'MEDIUM' }) | Out-Null
        }
        { $_ -in 4697, 7045 } {
            $hints.Add([PSCustomObject]@{ Id = 'service-install-review'; Title = 'Review new service install'; Severity = 'HIGH' }) | Out-Null
        }
        4769 {
            $hints.Add([PSCustomObject]@{ Id = 'kerberoast-watch'; Title = 'Kerberos ticket anomaly (possible Kerberoast)'; Severity = 'CRITICAL' }) | Out-Null
        }
        4624 {
            $hints.Add([PSCustomObject]@{ Id = 'logon-context'; Title = 'Correlate successful logon context'; Severity = 'INFO' }) | Out-Null
        }
    }
    return @($hints)
}

function Get-LocThreatEventLabel {
    param([int]$EventId)
    switch ($EventId) {
        1102 { return 'Audit log cleared' }
        4104 { return 'PowerShell ScriptBlock' }
        4624 { return 'Successful logon' }
        4625 { return 'Failed logon' }
        4688 { return 'Process creation' }
        4697 { return 'Service installed (Security)' }
        4769 { return 'Kerberos service ticket' }
        7045 { return 'Service installed (System)' }
        default { return "Event $EventId" }
    }
}
