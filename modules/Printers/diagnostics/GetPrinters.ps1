try {
    $printers = @()
    Get-Printer -ErrorAction Stop | ForEach-Object {
        $printers += [PSCustomObject]@{
            Name                 = $_.Name
            DriverName           = $_.DriverName
            PortName             = $_.PortName
            Shared               = [bool]$_.Shared
            Published            = [bool]$_.Published
            PrinterStatus        = [string]$_.PrinterStatus
            JobCount             = $_.JobCount
            Type                 = [string]$_.Type
        }
    }
    $spooler = Get-Service Spooler -ErrorAction SilentlyContinue
    return New-ApiResult -Success $true -Message ("{0} printer(s)" -f $printers.Count) -Data ([PSCustomObject]@{
        SpoolerStatus = if ($spooler) { [string]$spooler.Status } else { "Unknown" }
        Printers      = @($printers)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
