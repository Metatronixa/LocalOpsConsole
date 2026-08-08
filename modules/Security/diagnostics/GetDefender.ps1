# Security/diagnostics/GetDefender.ps1 — prefer fast CIM; avoid long WMI hangs
try {
    $status = $null
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
    }
    catch {
        # Fallback: registry / service hints
        $svc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        $data = [PSCustomObject]@{
            AMServiceEnabled      = ($svc -and $svc.Status -eq 'Running')
            AntispywareEnabled    = $null
            AntivirusEnabled      = $null
            RealTimeProtection    = $null
            IoavProtection        = $null
            NISEnabled            = $null
            AntivirusSignatureAge = $null
            QuickScanAge          = $null
            FullScanAge           = $null
            LastQuickScan         = $null
            ComputerState         = if ($svc) { [string]$svc.Status } else { "Unknown" }
            Note                  = "Get-MpComputerStatus unavailable: $($_.Exception.Message)"
        }
        return New-ApiResult -Success $true -Message "Defender status (limited)" -Data $data
    }

    $data = [PSCustomObject]@{
        AMServiceEnabled      = [bool]$status.AMServiceEnabled
        AntispywareEnabled    = [bool]$status.AntispywareEnabled
        AntivirusEnabled      = [bool]$status.AntivirusEnabled
        RealTimeProtection    = [bool]$status.RealTimeProtectionEnabled
        IoavProtection        = [bool]$status.IoavProtectionEnabled
        NISEnabled            = [bool]$status.NISEnabled
        AntivirusSignatureAge = $status.AntivirusSignatureAge
        QuickScanAge          = $status.QuickScanAge
        FullScanAge           = $status.FullScanAge
        LastQuickScan         = if ($status.QuickScanStartTime) { $status.QuickScanStartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        ComputerState         = [string]$status.ComputerState
    }
    New-ApiResult -Success $true -Message "Defender status" -Data $data
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
