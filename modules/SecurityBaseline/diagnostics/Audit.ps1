# modules/SecurityBaseline/diagnostics/Audit.ps1
# Read-only security baseline audit — never remediates

$checks = [System.Collections.ArrayList]::new()
$recommendations = [System.Collections.ArrayList]::new()

function Add-BaselineCheck {
    param(
        [string]$Name,
        [ValidateSet("Pass", "Warning", "Fail", "Unknown")][string]$Status,
        [string]$Detail,
        [int]$Weight = 5,
        [string]$Recommendation = ""
    )
    [void]$checks.Add([PSCustomObject]@{
        Name   = $Name
        Status = $Status
        Detail = $Detail
        Weight = $Weight
        Result = $Status
    })
    if ($Recommendation -and $Status -ne "Pass") {
        [void]$recommendations.Add($Recommendation)
    }
}

# --- Defender ---
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $rt = [bool]$mp.RealTimeProtectionEnabled
    $am = [bool]$mp.AntivirusEnabled
    if ($rt -and $am) {
        Add-BaselineCheck -Name "Microsoft Defender" -Status "Pass" -Detail "Realtime and antivirus enabled" -Weight 10
    }
    elseif ($am) {
        Add-BaselineCheck -Name "Microsoft Defender" -Status "Warning" -Detail "Antivirus on; realtime off" -Weight 10 `
            -Recommendation "Enable Defender real-time protection."
    }
    else {
        Add-BaselineCheck -Name "Microsoft Defender" -Status "Fail" -Detail "Defender antivirus not enabled" -Weight 10 `
            -Recommendation "Enable Microsoft Defender Antivirus and real-time protection."
    }
}
catch {
    Add-BaselineCheck -Name "Microsoft Defender" -Status "Unknown" -Detail $_.Exception.Message -Weight 10 `
        -Recommendation "Verify Defender cmdlets are available (Get-MpComputerStatus)."
}

# --- Firewall ---
try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
    $disabled = @($profiles | Where-Object { -not $_.Enabled })
    if ($disabled.Count -eq 0) {
        Add-BaselineCheck -Name "Windows Firewall" -Status "Pass" -Detail "All profiles enabled" -Weight 8
    }
    else {
        $names = ($disabled | ForEach-Object { $_.Name }) -join ", "
        Add-BaselineCheck -Name "Windows Firewall" -Status "Fail" -Detail "Disabled profiles: $names" -Weight 8 `
            -Recommendation "Enable Windows Firewall for: $names."
    }
}
catch {
    Add-BaselineCheck -Name "Windows Firewall" -Status "Unknown" -Detail $_.Exception.Message -Weight 8
}

# --- BitLocker ---
try {
    $vols = Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq "OperatingSystem" }
    if (-not $vols) {
        Add-BaselineCheck -Name "BitLocker" -Status "Unknown" -Detail "No OS volume reported" -Weight 8
    }
    else {
        $on = @($vols | Where-Object { $_.ProtectionStatus -eq "On" })
        if ($on.Count -eq $vols.Count) {
            Add-BaselineCheck -Name "BitLocker" -Status "Pass" -Detail "OS volume(s) protected" -Weight 8
        }
        else {
            Add-BaselineCheck -Name "BitLocker" -Status "Warning" -Detail "OS volume not fully protected" -Weight 8 `
                -Recommendation "Enable BitLocker on the operating system volume."
        }
    }
}
catch {
    Add-BaselineCheck -Name "BitLocker" -Status "Unknown" -Detail "Requires admin or BitLocker module: $($_.Exception.Message)" -Weight 8 `
        -Recommendation "Run elevated to audit BitLocker, or install BitLocker feature."
}

# --- TPM ---
try {
    $tpm = Get-Tpm -ErrorAction Stop
    if ($tpm.TpmPresent -and $tpm.TpmReady) {
        Add-BaselineCheck -Name "TPM" -Status "Pass" -Detail "TPM present and ready" -Weight 6
    }
    elseif ($tpm.TpmPresent) {
        Add-BaselineCheck -Name "TPM" -Status "Warning" -Detail "TPM present but not ready" -Weight 6 `
            -Recommendation "Initialize/ready the TPM in firmware or Windows."
    }
    else {
        Add-BaselineCheck -Name "TPM" -Status "Fail" -Detail "TPM not present" -Weight 6 `
            -Recommendation "Enable TPM in firmware for modern security features."
    }
}
catch {
    Add-BaselineCheck -Name "TPM" -Status "Unknown" -Detail $_.Exception.Message -Weight 6
}

# --- Secure Boot ---
try {
    $sb = Confirm-SecureBootUEFI -ErrorAction Stop
    if ($sb) {
        Add-BaselineCheck -Name "Secure Boot" -Status "Pass" -Detail "Secure Boot enabled" -Weight 7
    }
    else {
        Add-BaselineCheck -Name "Secure Boot" -Status "Fail" -Detail "Secure Boot disabled" -Weight 7 `
            -Recommendation "Enable Secure Boot in UEFI firmware."
    }
}
catch {
    Add-BaselineCheck -Name "Secure Boot" -Status "Unknown" -Detail "Not available (legacy BIOS or access denied)" -Weight 7
}

# --- Credential Guard ---
try {
    $cg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction Stop
    $running = $false
    if ($cg.SecurityServicesRunning -contains 1) { $running = $true }
    if ($running) {
        Add-BaselineCheck -Name "Credential Guard" -Status "Pass" -Detail "Credential Guard running" -Weight 5
    }
    else {
        Add-BaselineCheck -Name "Credential Guard" -Status "Warning" -Detail "Credential Guard not running" -Weight 5 `
            -Recommendation "Enable Credential Guard on supported enterprise SKUs."
    }
}
catch {
    Add-BaselineCheck -Name "Credential Guard" -Status "Unknown" -Detail $_.Exception.Message -Weight 5
}

# --- LSA Protection ---
try {
    $lsa = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue
    if ($lsa -and $lsa.RunAsPPL -ge 1) {
        Add-BaselineCheck -Name "LSA Protection" -Status "Pass" -Detail "RunAsPPL enabled" -Weight 5
    }
    else {
        Add-BaselineCheck -Name "LSA Protection" -Status "Warning" -Detail "RunAsPPL not enabled" -Weight 5 `
            -Recommendation "Enable LSA protection (RunAsPPL) via security policy."
    }
}
catch {
    Add-BaselineCheck -Name "LSA Protection" -Status "Unknown" -Detail $_.Exception.Message -Weight 5
}

# --- UAC ---
try {
    $uac = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction Stop
    $enable = [int]$uac.EnableLUA
    $consent = [int]$uac.ConsentPromptBehaviorAdmin
    if ($enable -eq 1 -and $consent -ge 1) {
        Add-BaselineCheck -Name "UAC" -Status "Pass" -Detail "UAC enabled (consent=$consent)" -Weight 6
    }
    elseif ($enable -eq 1) {
        Add-BaselineCheck -Name "UAC" -Status "Warning" -Detail "UAC on but admin prompt weak ($consent)" -Weight 6 `
            -Recommendation "Raise UAC ConsentPromptBehaviorAdmin to at least 2."
    }
    else {
        Add-BaselineCheck -Name "UAC" -Status "Fail" -Detail "UAC disabled" -Weight 6 `
            -Recommendation "Re-enable User Account Control (EnableLUA=1)."
    }
}
catch {
    Add-BaselineCheck -Name "UAC" -Status "Unknown" -Detail $_.Exception.Message -Weight 6
}

# --- Windows Update service ---
try {
    $wu = Get-Service -Name wuauserv -ErrorAction Stop
    if ($wu.Status -eq "Running") {
        Add-BaselineCheck -Name "Windows Update" -Status "Pass" -Detail "wuauserv running ($($wu.StartType))" -Weight 6
    }
    else {
        Add-BaselineCheck -Name "Windows Update" -Status "Warning" -Detail "wuauserv $($wu.Status)" -Weight 6 `
            -Recommendation "Ensure Windows Update service can run."
    }
}
catch {
    Add-BaselineCheck -Name "Windows Update" -Status "Unknown" -Detail $_.Exception.Message -Weight 6
}

# --- SMBv1 ---
try {
    $smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    if ($smb -and $smb.State -eq "Enabled") {
        Add-BaselineCheck -Name "SMBv1" -Status "Fail" -Detail "SMBv1 feature enabled" -Weight 7 `
            -Recommendation "Disable SMBv1 (legacy protocol)."
    }
    else {
        Add-BaselineCheck -Name "SMBv1" -Status "Pass" -Detail "SMBv1 not enabled" -Weight 7
    }
}
catch {
    try {
        $smbServer = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smbServer.EnableSMB1Protocol) {
            Add-BaselineCheck -Name "SMBv1" -Status "Fail" -Detail "SMB1 protocol enabled on server" -Weight 7 `
                -Recommendation "Disable SMBv1 via Set-SmbServerConfiguration."
        }
        else {
            Add-BaselineCheck -Name "SMBv1" -Status "Pass" -Detail "SMB1 protocol disabled" -Weight 7
        }
    }
    catch {
        Add-BaselineCheck -Name "SMBv1" -Status "Unknown" -Detail "Could not query SMBv1 state" -Weight 7
    }
}

# --- RDP ---
try {
    $rdp = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction Stop
    $nla = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue
    if ([int]$rdp.fDenyTSConnections -eq 1) {
        Add-BaselineCheck -Name "Remote Desktop" -Status "Pass" -Detail "RDP connections denied" -Weight 5
    }
    else {
        $nlaOk = $nla -and [int]$nla.UserAuthentication -eq 1
        if ($nlaOk) {
            Add-BaselineCheck -Name "Remote Desktop" -Status "Warning" -Detail "RDP enabled with NLA" -Weight 5 `
                -Recommendation "Restrict RDP exposure; keep NLA enabled; prefer VPN."
        }
        else {
            Add-BaselineCheck -Name "Remote Desktop" -Status "Fail" -Detail "RDP enabled without NLA" -Weight 5 `
                -Recommendation "Enable Network Level Authentication for RDP or disable RDP."
        }
    }
}
catch {
    Add-BaselineCheck -Name "Remote Desktop" -Status "Unknown" -Detail $_.Exception.Message -Weight 5
}

# --- WinRM ---
try {
    $winrm = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if (-not $winrm -or $winrm.Status -ne "Running") {
        Add-BaselineCheck -Name "WinRM" -Status "Pass" -Detail "WinRM not running" -Weight 4
    }
    else {
        Add-BaselineCheck -Name "WinRM" -Status "Warning" -Detail "WinRM running ($($winrm.StartType))" -Weight 4 `
            -Recommendation "Harden WinRM (HTTPS, auth, firewall scope) if remoting is required."
    }
}
catch {
    Add-BaselineCheck -Name "WinRM" -Status "Unknown" -Detail $_.Exception.Message -Weight 4
}

# --- PowerShell logging ---
try {
    $scriptBlock = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -ErrorAction SilentlyContinue
    $moduleLog = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" -ErrorAction SilentlyContinue
    $sbOn = $scriptBlock -and [int]$scriptBlock.EnableScriptBlockLogging -eq 1
    $mlOn = $moduleLog -and [int]$moduleLog.EnableModuleLogging -eq 1
    if ($sbOn) {
        Add-BaselineCheck -Name "PowerShell Logging" -Status "Pass" -Detail "Script block logging enabled$(if ($mlOn) { '; module logging on' })" -Weight 5
    }
    else {
        Add-BaselineCheck -Name "PowerShell Logging" -Status "Warning" -Detail "Script block logging not enabled" -Weight 5 `
            -Recommendation "Enable PowerShell Script Block Logging via GPO/Intune."
    }
}
catch {
    Add-BaselineCheck -Name "PowerShell Logging" -Status "Unknown" -Detail $_.Exception.Message -Weight 5
}

# --- Event Log status ---
try {
    $logs = @("System", "Application", "Security")
    $bad = @()
    foreach ($ln in $logs) {
        $el = Get-WinEvent -ListLog $ln -ErrorAction SilentlyContinue
        if (-not $el -or -not $el.IsEnabled) { $bad += $ln }
    }
    if ($bad.Count -eq 0) {
        Add-BaselineCheck -Name "Event Log" -Status "Pass" -Detail "System/Application/Security enabled" -Weight 5
    }
    else {
        Add-BaselineCheck -Name "Event Log" -Status "Fail" -Detail "Disabled or missing: $($bad -join ', ')" -Weight 5 `
            -Recommendation "Re-enable critical Windows event logs: $($bad -join ', ')."
    }
}
catch {
    Add-BaselineCheck -Name "Event Log" -Status "Unknown" -Detail $_.Exception.Message -Weight 5
}

# --- Installed security software (WMI product / Defender as primary) ---
try {
    $avs = @()
    try {
        $avs = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
    }
    catch { Write-Debug $_.Exception.Message }
    if ($avs.Count -gt 0) {
        $names = ($avs | ForEach-Object { $_.displayName } | Select-Object -Unique) -join "; "
        Add-BaselineCheck -Name "Security Software" -Status "Pass" -Detail $names -Weight 4
    }
    else {
        Add-BaselineCheck -Name "Security Software" -Status "Warning" -Detail "No SecurityCenter2 AV products listed" -Weight 4 `
            -Recommendation "Confirm an antivirus product is installed and registered."
    }
}
catch {
    Add-BaselineCheck -Name "Security Software" -Status "Unknown" -Detail $_.Exception.Message -Weight 4
}

# --- Audit policy (sample: process creation) ---
try {
    $auditOut = auditpol.exe /get /category:"Detailed Tracking" 2>$null | Out-String
    if ($auditOut -match "Process Creation\s+Success") {
        Add-BaselineCheck -Name "Audit Policy" -Status "Pass" -Detail "Process Creation success auditing present" -Weight 4
    }
    else {
        Add-BaselineCheck -Name "Audit Policy" -Status "Warning" -Detail "Process Creation success auditing not clearly enabled" -Weight 4 `
            -Recommendation "Enable Detailed Tracking / Process Creation success auditing."
    }
}
catch {
    Add-BaselineCheck -Name "Audit Policy" -Status "Unknown" -Detail "auditpol unavailable" -Weight 4
}

# Score: weighted Pass=full, Warning=half, Fail/Unknown=0
$totalWeight = 0
$earned = 0.0
foreach ($c in $checks) {
    $w = [double]$c.Weight
    $totalWeight += $w
    switch ($c.Status) {
        "Pass"    { $earned += $w }
        "Warning" { $earned += ($w * 0.5) }
        default   { }
    }
}
$score = if ($totalWeight -gt 0) { [int][math]::Round(100.0 * $earned / $totalWeight) } else { 0 }

$passed = @($checks | Where-Object { $_.Status -eq "Pass" }).Count
$total = $checks.Count
$failed = @($checks | Where-Object { $_.Status -eq "Fail" }).Count

$risk = if ($score -ge 85 -and $failed -eq 0) { "Low" }
    elseif ($score -ge 70) { "Moderate" }
    elseif ($score -ge 50) { "High" }
    else { "Critical" }

$data = [PSCustomObject]@{
    Score            = $score
    RiskRating       = $risk
    Risk             = $risk
    Compliance       = [PSCustomObject]@{
        Passed = $passed
        Failed = $failed
        Total  = $total
        Percent = if ($total -gt 0) { [int][math]::Round(100.0 * $passed / $total) } else { 0 }
    }
    Checks           = @($checks)
    Controls         = @($checks)
    Recommendations  = @($recommendations | Select-Object -Unique)
    GeneratedAt      = (Get-Date).ToUniversalTime().ToString("o")
}

New-ApiResult -Success $true -Message "Security baseline audit complete" -Data $data
