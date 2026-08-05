param(
    [Parameter(Mandatory)]
    [string]$PrinterName
)

try {
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if (-not $printer) {
        # Attempt WMI-only ghost removal
        $escaped = $PrinterName.Replace("\", "\\").Replace("'", "''")
        $wmi = Get-CimInstance -ClassName Win32_Printer -Filter "Name='$escaped'" -ErrorAction SilentlyContinue
        if ($wmi) {
            $null = Invoke-CimMethod -InputObject $wmi -MethodName Delete -ErrorAction Stop
            return New-ApiResult -Success $true -Message "Removed ghost printer (WMI): $PrinterName" -Data ([PSCustomObject]@{
                PrinterName = $PrinterName
                Method      = "WMI"
            })
        }
        return New-ApiResult -Success $false -Message "Printer not found: $PrinterName"
    }

    $portName = [string]$printer.PortName
    Remove-Printer -Name $PrinterName -ErrorAction Stop

    $othersOnPort = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $portName })
    if ($othersOnPort.Count -eq 0 -and $portName) {
        Remove-PrinterPort -Name $portName -ErrorAction SilentlyContinue
    }

    return New-ApiResult -Success $true -Message "Removed printer: $PrinterName" -Data ([PSCustomObject]@{
        PrinterName = $PrinterName
        PortName    = $portName
        Method      = "Remove-Printer"
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
