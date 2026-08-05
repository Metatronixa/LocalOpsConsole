param([string]$PortName = "")

try {
    $ports = if ($PortName) {
        @(Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)
    }
    else {
        @(Get-PrinterPort -ErrorAction SilentlyContinue)
    }

    $printerMap = @{}
    Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
        $pn = [string]$_.PortName
        if (-not $printerMap.ContainsKey($pn)) { $printerMap[$pn] = @() }
        $printerMap[$pn] += [string]$_.Name
    }

    $data = @($ports | ForEach-Object {
        $info = Get-LocPrinterPortInfo -PortName $_.Name
        $mapped = if ($printerMap.ContainsKey($_.Name)) { @($printerMap[$_.Name]) } else { @() }
        [PSCustomObject]@{
            PortName     = [string]$_.Name
            Type         = if ($info) { $info.Type } else { Get-LocPortType -PortName $_.Name -PortObject $_ }
            HostAddress  = if ($info) { $info.HostAddress } else { "" }
            PortNumber   = if ($info) { $info.PortNumber } else { 0 }
            SNMPEnabled  = if ($info) { $info.SNMPEnabled } else { $false }
            Description  = if ($info) { $info.Description } else { "" }
            PrinterNames = $mapped
        }
    })

    return New-ApiResult -Success $true -Message ("{0} port(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
