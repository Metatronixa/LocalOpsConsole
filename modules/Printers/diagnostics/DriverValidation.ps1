# Printers/diagnostics/DriverValidation.ps1
try {
    $printers = @(Get-Printer -ErrorAction Stop)
    $drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue)
    $driverNames = @($drivers | ForEach-Object { $_.Name })
    $items = @()
    foreach ($p in $printers) {
        $hasDriver = $driverNames -contains $p.DriverName
        $port = Get-PrinterPort -Name $p.PortName -ErrorAction SilentlyContinue
        $items += [PSCustomObject]@{
            Printer     = $p.Name
            DriverName  = $p.DriverName
            DriverOk    = $hasDriver
            PortName    = $p.PortName
            PortExists  = [bool]$port
            Status      = [string]$p.PrinterStatus
            Issues      = @(
                $(if (-not $hasDriver) { "Driver not registered" }),
                $(if (-not $port) { "Port missing" })
            ) | Where-Object { $_ }
        }
    }

    New-ApiResult -Success $true -Message "Printer driver validation" -Data @{
        Items         = @($items)
        DriverCount   = $drivers.Count
        ProblemCount  = @($items | Where-Object { $_.Issues.Count -gt 0 }).Count
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
