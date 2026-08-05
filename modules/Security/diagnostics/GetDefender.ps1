try {
    $status = Get-MpComputerStatus -ErrorAction Stop
    $data = [PSCustomObject]@{
        AMServiceEnabled        = $status.AMServiceEnabled
        AntispywareEnabled      = $status.AntispywareEnabled
        AntivirusEnabled        = $status.AntivirusEnabled
        RealTimeProtection      = $status.RealTimeProtectionEnabled
        IoavProtection          = $status.IoavProtectionEnabled
        NISEnabled              = $status.NISEnabled
        AntivirusSignatureAge   = $status.AntivirusSignatureAge
        QuickScanAge            = $status.QuickScanAge
        FullScanAge             = $status.FullScanAge
        LastQuickScan           = if ($status.QuickScanStartTime) { $status.QuickScanStartTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        ComputerState           = [string]$status.ComputerState
    }
    return New-ApiResult -Success $true -Message "Defender status" -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
