param([string]$PrinterName = "")
try {
    $jobs = if ($PrinterName) {
        Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue
    } else {
        Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
            Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
        }
    }
    $data = @($jobs | ForEach-Object {
        [PSCustomObject]@{
            PrinterName = $_.PrinterName
            Id          = $_.Id
            Document    = $_.DocumentName
            JobStatus   = [string]$_.JobStatus
            Size        = $_.Size
            Submitted   = if ($_.SubmittedTime) { $_.SubmittedTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        }
    })
    return New-ApiResult -Success $true -Message ("{0} job(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
