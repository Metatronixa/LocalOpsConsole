# AgentCommands.Security.ps1 - Security baseline handlers
if (-not $script:LocAgentHandlers) { $script:LocAgentHandlers = @{} }

$script:LocAgentHandlers['AuditSecurityBaseline'] = {
    param($r)
    & $r.AddLog "Auditing security baseline (compact)..."
    $checks = New-Object System.Collections.ArrayList
    function Add-AgentCheck([string]$Name, [string]$Status, [string]$Detail) {
        [void]$checks.Add([PSCustomObject]@{ Name = $Name; Status = $Status; Detail = $Detail })
        switch ($Status) {
            'Pass' { $script:__acPass++ }
            'Fail' { $script:__acFail++ }
            'Warning' { $script:__acWarn++ }
            default { $script:__acUnk++ }
        }
    }
    $script:__acPass = 0; $script:__acFail = 0; $script:__acWarn = 0; $script:__acUnk = 0
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ([bool]$mp.RealTimeProtectionEnabled -and [bool]$mp.AntivirusEnabled) {
            Add-AgentCheck -Name 'Microsoft Defender' -Status 'Pass' -Detail 'Realtime and antivirus enabled'
        }
        elseif ([bool]$mp.AntivirusEnabled) {
            Add-AgentCheck -Name 'Microsoft Defender' -Status 'Warning' -Detail 'Antivirus on; realtime off'
        }
        else {
            Add-AgentCheck -Name 'Microsoft Defender' -Status 'Fail' -Detail 'Defender not fully enabled'
        }
    }
    catch { Add-AgentCheck -Name 'Microsoft Defender' -Status 'Unknown' -Detail $_.Exception.Message }
    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        $disabled = @($profiles | Where-Object { -not $_.Enabled })
        if ($disabled.Count -eq 0) {
            Add-AgentCheck -Name 'Windows Firewall' -Status 'Pass' -Detail 'All profiles enabled'
        }
        else {
            Add-AgentCheck -Name 'Windows Firewall' -Status 'Fail' -Detail ("Disabled: {0}" -f (($disabled | ForEach-Object Name) -join ', '))
        }
    }
    catch { Add-AgentCheck -Name 'Windows Firewall' -Status 'Unknown' -Detail $_.Exception.Message }

    try {
        $vols = @(Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq 'OperatingSystem' })
        if ($vols.Count -eq 0) {
            Add-AgentCheck -Name 'BitLocker' -Status 'Warning' -Detail 'No OS volume reported'
        }
        else {
            $prot = @($vols | Where-Object { $_.ProtectionStatus -eq 'On' })
            if ($prot.Count -eq $vols.Count) {
                Add-AgentCheck -Name 'BitLocker' -Status 'Pass' -Detail 'OS volume protected'
            }
            else {
                Add-AgentCheck -Name 'BitLocker' -Status 'Fail' -Detail 'OS volume not fully protected'
            }
        }
    }
    catch { Add-AgentCheck -Name 'BitLocker' -Status 'Unknown' -Detail $_.Exception.Message }

    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($tpm -and $tpm.TpmPresent -and $tpm.TpmReady) {
            Add-AgentCheck -Name 'TPM' -Status 'Pass' -Detail 'TPM present and ready'
        }
        elseif ($tpm -and $tpm.TpmPresent) {
            Add-AgentCheck -Name 'TPM' -Status 'Warning' -Detail 'TPM present but not ready'
        }
        else {
            Add-AgentCheck -Name 'TPM' -Status 'Fail' -Detail 'TPM not present'
        }
    }
    catch { Add-AgentCheck -Name 'TPM' -Status 'Unknown' -Detail $_.Exception.Message }

    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        if ($sb) { Add-AgentCheck -Name 'Secure Boot' -Status 'Pass' -Detail 'Secure Boot enabled' }
        else { Add-AgentCheck -Name 'Secure Boot' -Status 'Fail' -Detail 'Secure Boot disabled' }
    }
    catch { Add-AgentCheck -Name 'Secure Boot' -Status 'Unknown' -Detail $_.Exception.Message }

    $total = $checks.Count
    $score = if ($total -gt 0) {
        [int][math]::Round(100.0 * $script:__acPass / $total)
    } else { 0 }
    $r.Success = $true
    $r.Message = "Baseline audit score $score%"
    $r.Data = @{
        Score   = $score
        Pass    = $script:__acPass
        Fail    = $script:__acFail
        Warning = $script:__acWarn
        Unknown = $script:__acUnk
        Checks  = @($checks)
    }
}

$script:LocAgentHandlers['ApplySecurityPolicy'] = {
    param($r)
    $packId = "hardening-basic"
    if ($r.Payload -and $r.Payload.PackId) { $packId = [string]$r.Payload.PackId }
    $allowedPacks = @('hardening-basic')
    if ($allowedPacks -notcontains $packId) { throw "Unknown or disallowed pack: $packId" }

    $controlIds = @('firewall-enable-all', 'defender-realtime-on')
    if ($r.Payload -and $r.Payload.ControlIds) {
        $controlIds = @($r.Payload.ControlIds | ForEach-Object { [string]$_ })
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "ApplySecurityPolicy requires an elevated agent (Administrator)" }

    & $r.AddLog "Applying policy pack $packId..."
    $results = New-Object System.Collections.ArrayList
    foreach ($cid in $controlIds) {
        $ok = $false
        $detail = ""
        try {
            switch ($cid) {
                'firewall-enable-all' {
                    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
                    $ok = $true
                    $detail = "Firewall Domain/Private/Public enabled"
                }
                'defender-realtime-on' {
                    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
                    $ok = $true
                    $detail = "Defender realtime monitoring enabled"
                }
                default {
                    $detail = "Unknown control id (skipped)"
                }
            }
        }
        catch {
            $ok = $false
            $detail = $_.Exception.Message
        }
        & $r.AddLog ("{0}: {1} - {2}" -f $cid, $(if ($ok) { 'OK' } else { 'FAIL' }), $detail)
        [void]$results.Add([PSCustomObject]@{ Id = $cid; Ok = $ok; Detail = $detail })
    }
    $failed = @($results | Where-Object { -not $_.Ok }).Count
    $r.Success = ($failed -eq 0)
    $r.Message = if ($r.Success) { "Applied $packId ($($results.Count) controls)" } else { "Applied $packId with $failed failure(s)" }
    $r.Data = @{
        PackId  = $packId
        Results = @($results)
    }
}
