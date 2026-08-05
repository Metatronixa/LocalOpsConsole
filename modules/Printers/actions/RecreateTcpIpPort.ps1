param(
    [Parameter(Mandatory)]
    [string]$PrinterName
)

try {
    $printer = Get-Printer -Name $PrinterName -ErrorAction Stop
    $portName = [string]$printer.PortName
    $portInfo = Get-LocPrinterPortInfo -PortName $portName
    $portType = if ($portInfo) { $portInfo.Type } else { Get-LocPortType -PortName $portName }

    if ($portType -ne "TCP/IP") {
        return New-ApiResult -Success $false -Message "RecreateTcpIpPort only applies to TCP/IP ports (port: $portName)"
    }

    $hostAddr = if ($portInfo -and $portInfo.HostAddress) { $portInfo.HostAddress } else { "" }
    if ([string]::IsNullOrWhiteSpace($hostAddr) -and $portName -match '(\d{1,3}(?:\.\d{1,3}){3})') {
        $hostAddr = $Matches[1]
    }
    if ([string]::IsNullOrWhiteSpace($hostAddr)) {
        return New-ApiResult -Success $false -Message "Could not determine host address for port $portName"
    }

    $portNumber = if ($portInfo -and $portInfo.PortNumber -gt 0) { $portInfo.PortNumber } else { 9100 }
    $newPortName = "IP_$hostAddr"

    if (Get-PrinterPort -Name $newPortName -ErrorAction SilentlyContinue) {
        Remove-PrinterPort -Name $newPortName -ErrorAction SilentlyContinue
    }
    if ($portName -ne $newPortName -and (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
        Remove-PrinterPort -Name $portName -ErrorAction SilentlyContinue
    }

    Add-PrinterPort -Name $newPortName -PrinterHostAddress $hostAddr -PortNumber $portNumber -ErrorAction Stop
    Set-Printer -Name $PrinterName -PortName $newPortName -ErrorAction Stop

    return New-ApiResult -Success $true -Message "Recreated TCP/IP port $newPortName for $PrinterName" -Data ([PSCustomObject]@{
        PrinterName = $PrinterName
        PortName    = $newPortName
        HostAddress = $hostAddr
        PortNumber  = $portNumber
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
