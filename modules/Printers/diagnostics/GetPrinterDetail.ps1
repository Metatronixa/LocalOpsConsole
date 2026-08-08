param(
    [Parameter(Mandatory)]
    [string]$PrinterName
)

try {
    $printer = Get-Printer -Name $PrinterName -ErrorAction Stop
    $defaultName = Get-LocDefaultPrinterName
    $portInfo = Get-LocPrinterPortInfo -PortName $printer.PortName
    $driverInfo = Get-LocPrinterDriverInfo -DriverName $printer.DriverName
    $lastError = Get-LocPrinterLastError -PrinterName $PrinterName

    $local = $true
    try {
        $wmi = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$($PrinterName.Replace("'","''"))'" -ErrorAction SilentlyContinue
        if ($wmi -and $null -ne $wmi.Local) { $local = [bool]$wmi.Local }
    }
    catch { Write-Debug $_.Exception.Message }

    $printProcessor = ""
    try {
        if ($wmi -and $wmi.PrintProcessor) { $printProcessor = [string]$wmi.PrintProcessor }
    }
    catch { Write-Debug $_.Exception.Message }

    return New-ApiResult -Success $true -Message "Printer detail: $PrinterName" -Data ([PSCustomObject]@{
        Name           = [string]$printer.Name
        Status         = [string]$printer.PrinterStatus
        Default        = [bool]$printer.Default -or ($defaultName -eq $PrinterName)
        DriverName     = [string]$printer.DriverName
        DriverVersion  = $driverInfo.Version
        DriverDate     = $driverInfo.Date
        PortName       = [string]$printer.PortName
        PortHost       = if ($portInfo) { $portInfo.HostAddress } else { "" }
        PortType       = if ($portInfo) { $portInfo.Type } else { Get-LocPortType -PortName $printer.PortName }
        Shared         = [bool]$printer.Shared
        Local          = $local
        PrintProcessor = $printProcessor
        JobCount       = [int]$printer.JobCount
        Type           = [string]$printer.Type
        LastError      = $lastError
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
