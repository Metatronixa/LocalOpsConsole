# Printers/diagnostics/QueueAnalytics.ps1
try {
    $printers = @(Get-Printer -ErrorAction Stop)
    $jobs = @(Get-PrintJob -ErrorAction SilentlyContinue)
    $byPrinter = @{}
    foreach ($j in $jobs) {
        $n = [string]$j.PrinterName
        if (-not $byPrinter.ContainsKey($n)) {
            $byPrinter[$n] = [PSCustomObject]@{ Printer = $n; Jobs = 0; Error = 0; Printing = 0; Paused = 0 }
        }
        $byPrinter[$n].Jobs++
        $st = [string]$j.JobStatus
        if ($st -match "Error") { $byPrinter[$n].Error++ }
        if ($st -match "Printing") { $byPrinter[$n].Printing++ }
        if ($st -match "Paused") { $byPrinter[$n].Paused++ }
    }

    $spooler = Get-Service Spooler -ErrorAction SilentlyContinue
    New-ApiResult -Success $true -Message "Printer queue analytics" -Data @{
        PrinterCount = $printers.Count
        TotalJobs    = $jobs.Count
        Queues       = @($byPrinter.Values)
        Spooler      = if ($spooler) { [PSCustomObject]@{ Status = [string]$spooler.Status; StartType = [string]$spooler.StartType } } else { $null }
        Printers     = @($printers | Select-Object Name, DriverName, PortName, PrinterStatus, Shared, Type)
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
