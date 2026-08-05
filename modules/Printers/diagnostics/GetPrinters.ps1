try {
    $defaultName = Get-LocDefaultPrinterName
    $portCache = @{}
    $printers = @()

    Get-Printer -ErrorAction Stop | ForEach-Object {
        $portName = [string]$_.PortName
        $portHost = ""
        if ($portName) {
            if (-not $portCache.ContainsKey($portName)) {
                $pi = Get-LocPrinterPortInfo -PortName $portName
                $portCache[$portName] = if ($pi) { $pi.HostAddress } else { "" }
            }
            $portHost = $portCache[$portName]
        }

        $printers += [PSCustomObject]@{
            Name          = $_.Name
            DriverName    = $_.DriverName
            PortName      = $portName
            PortHost      = $portHost
            Default       = [bool]$_.Default -or ($defaultName -and $_.Name -eq $defaultName)
            Shared        = [bool]$_.Shared
            Published     = [bool]$_.Published
            PrinterStatus = [string]$_.PrinterStatus
            JobCount      = $_.JobCount
            Type          = [string]$_.Type
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
