# core/SecurityScore.ps1 - Security Center aggregate score

function Get-LocSecurityScorePayload {
    $checks = [System.Collections.ArrayList]::new()
    $score = 100
    $lastScan = "Unknown"

    # Defender
    try {
        $mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($mp) {
            if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
                [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Healthy"; Detail = "Realtime protection on" })
            }
            elseif ($mp.AntivirusEnabled) {
                [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Warning"; Detail = "Realtime off" })
                $score -= 12
            }
            else {
                [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Critical"; Detail = "Antivirus disabled" })
                $score -= 30
            }
            try {
                if ($mp.QuickScanEndTime) { $lastScan = ([datetime]$mp.QuickScanEndTime).ToString("yyyy-MM-dd HH:mm") }
                elseif ($mp.FullScanEndTime) { $lastScan = ([datetime]$mp.FullScanEndTime).ToString("yyyy-MM-dd HH:mm") }
            }
            catch { }
        }
        else {
            [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Warning"; Detail = "Status unavailable" })
            $score -= 8
        }
    }
    catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "Defender"; Status = "Warning"; Detail = "Status unavailable" })
        $score -= 8
    }

    # Firewall
    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
        $disabled = @($profiles | Where-Object { -not $_.Enabled })
        if ($profiles.Count -eq 0) {
            [void]$checks.Add([PSCustomObject]@{ Name = "Firewall"; Status = "Warning"; Detail = "Unable to query" })
            $score -= 5
        }
        elseif ($disabled.Count -eq 0) {
            [void]$checks.Add([PSCustomObject]@{ Name = "Firewall"; Status = "Healthy"; Detail = "All profiles on" })
        }
        else {
            $names = ($disabled | ForEach-Object { $_.Name }) -join ", "
            [void]$checks.Add([PSCustomObject]@{ Name = "Firewall"; Status = "Critical"; Detail = "Disabled: $names" })
            $score -= 20
        }
    }
    catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "Firewall"; Status = "Warning"; Detail = "Unable to query" })
        $score -= 5
    }

    # BitLocker (registry peek — Get-BitLockerVolume is often slow without elevation)
    try {
        $blStatus = $null
        $osDrive = $env:SystemDrive
        if (-not $osDrive) { $osDrive = "C:" }
        $blKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\BitLocker"
        # Prefer Protection Status via manage-bde is slow; use Win32_EncryptableVolume only if quick
        if (Test-IsAdmin) {
            $bl = @(Get-BitLockerVolume -MountPoint $osDrive -ErrorAction SilentlyContinue)
            if ($bl.Count -gt 0) { $blStatus = [string]$bl[0].ProtectionStatus }
        }
        if ($null -eq $blStatus) {
            # Non-admin / unavailable: don't block the score on BitLocker cmdlets
            [void]$checks.Add([PSCustomObject]@{ Name = "BitLocker"; Status = "Information"; Detail = "Requires elevation to verify" })
        }
        elseif ($blStatus -eq "On") {
            [void]$checks.Add([PSCustomObject]@{ Name = "BitLocker"; Status = "Healthy"; Detail = "OS volume protected" })
        }
        else {
            [void]$checks.Add([PSCustomObject]@{ Name = "BitLocker"; Status = "Warning"; Detail = "OS volume unprotected ($blStatus)" })
            $score -= 8
        }
    }
    catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "BitLocker"; Status = "Information"; Detail = "Unable to query" })
    }

    # LSA
    try {
        $lsa = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -ErrorAction SilentlyContinue
        if ($lsa -and [int]$lsa.RunAsPPL -ge 1) {
            [void]$checks.Add([PSCustomObject]@{ Name = "LSA"; Status = "Healthy"; Detail = "RunAsPPL enabled" })
        }
        else {
            [void]$checks.Add([PSCustomObject]@{ Name = "LSA"; Status = "Warning"; Detail = "RunAsPPL not enabled" })
            $score -= 5
        }
    }
    catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "LSA"; Status = "Warning"; Detail = "Unable to query" })
        $score -= 3
    }

    # Credential Guard
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
        if ($dg -and $dg.SecurityServicesRunning -contains 1) {
            [void]$checks.Add([PSCustomObject]@{ Name = "Credential Guard"; Status = "Healthy"; Detail = "Running" })
        }
        else {
            [void]$checks.Add([PSCustomObject]@{ Name = "Credential Guard"; Status = "Information"; Detail = "Not running" })
        }
    }
    catch {
        [void]$checks.Add([PSCustomObject]@{ Name = "Credential Guard"; Status = "Information"; Detail = "Unable to query" })
    }

    [void]$checks.Add([PSCustomObject]@{ Name = "Last Scan"; Status = "Information"; Detail = $lastScan })

    $score = [Math]::Max(0, [Math]::Min(100, $score))
    $checkArr = @($checks)
    return [PSCustomObject]@{
        Score           = $score
        Defender        = ($checkArr | Where-Object { $_.Name -eq "Defender" } | Select-Object -First 1)
        Firewall        = ($checkArr | Where-Object { $_.Name -eq "Firewall" } | Select-Object -First 1)
        BitLocker       = ($checkArr | Where-Object { $_.Name -eq "BitLocker" } | Select-Object -First 1)
        LSA             = ($checkArr | Where-Object { $_.Name -eq "LSA" } | Select-Object -First 1)
        CredentialGuard = ($checkArr | Where-Object { $_.Name -eq "Credential Guard" } | Select-Object -First 1)
        LastScan        = $lastScan
        Checks          = $checkArr
        Updated         = (Get-Date).ToUniversalTime().ToString("o")
    }
}
