# core/TaskRunnerExtras.ps1 - VPN / GPU / battery / host telemetry + Update-LocTelemetry

function Update-LocTelemetryExtras {
    param([object]$Os)

    try {
        $vpnConn = $null
        if (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue) {
            $vpnConn = @(Get-VpnConnection -ErrorAction SilentlyContinue |
                Where-Object { $_.ConnectionStatus -eq 'Connected' } |
                Select-Object -First 1)
        }
        if ($vpnConn) {
            $v = $vpnConn[0]
            $adapterName = $null
            try {
                $adapterName = @(Get-NetAdapter -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Status -eq 'Up' -and
                        ($_.InterfaceDescription -match '(?i)vpn|wan miniport|tap|tun|wireguard|ras' -or $_.Name -match '(?i)vpn')
                    } |
                    Select-Object -First 1 -ExpandProperty Name)
            }
            catch { Write-Debug $_.Exception.Message }
            $script:LocTelemetry.Vpn = [PSCustomObject]@{
                Connected        = $true
                Name             = [string]$v.Name
                ServerAddress    = [string]$v.ServerAddress
                TunnelType       = [string]$v.TunnelType
                ConnectionStatus = [string]$v.ConnectionStatus
                Adapter          = $adapterName
            }
        }
        else {
            $script:LocTelemetry.Vpn = $null
        }
    }
    catch {
        $script:LocTelemetry.Vpn = $null
    }

    try {
        $gpu = Get-CimInstance -ClassName Win32_VideoController -Property Name, DriverVersion, AdapterRAM -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic' } |
            Select-Object -First 1
        if (-not $gpu) {
            $gpu = Get-CimInstance -ClassName Win32_VideoController -Property Name, DriverVersion, AdapterRAM -ErrorAction Stop |
                Select-Object -First 1
        }
        if ($gpu) {
            $ramGb = $null
            if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                $ramGb = [math]::Round([double]$gpu.AdapterRAM / 1GB, 1)
            }
            $script:LocTelemetry.Gpu = [PSCustomObject]@{
                Name          = [string]$gpu.Name
                DriverVersion = [string]$gpu.DriverVersion
                AdapterRAMGB  = $ramGb
            }
        }
        else {
            $script:LocTelemetry.Gpu = $null
        }
    }
    catch {
        $script:LocTelemetry.Gpu = $null
    }

    try {
        $bat = Get-CimInstance -ClassName Win32_Battery -Property EstimatedChargeRemaining, BatteryStatus, Name -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($bat) {
            $script:LocTelemetry.Battery = [PSCustomObject]@{
                ChargePct = if ($null -ne $bat.EstimatedChargeRemaining) { [int]$bat.EstimatedChargeRemaining } else { $null }
                Status    = [string]$bat.BatteryStatus
                Name      = [string]$bat.Name
            }
        }
        else {
            $script:LocTelemetry.Battery = $null
        }
    }
    catch {
        $script:LocTelemetry.Battery = $null
    }

    # Problem devices — NEVER full Get-PnpDevice on hot path (can take 10–60s).
    if (-not $script:LocTelemetry.Devices) {
        $script:LocTelemetry.Devices = [PSCustomObject]@{ ProblemCount = $null }
    }

    try {
        $boot = $Os.LastBootUpTime
        $uptime = (Get-Date) - $boot
        $formatted = "{0}d {1:D2}h {2:D2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes
        $script:LocTelemetry.Host = [PSCustomObject]@{
            ComputerName    = if ($Os.CSName) { [string]$Os.CSName } else { $env:COMPUTERNAME }
            LastBoot        = $boot.ToString("yyyy-MM-dd HH:mm:ss")
            UptimeFormatted = $formatted
            PendingReboot   = (Test-LocPendingReboot)
        }
    }
    catch {
        $script:LocTelemetry.Host = [PSCustomObject]@{
            ComputerName    = $env:COMPUTERNAME
            LastBoot        = $null
            UptimeFormatted = "--"
            PendingReboot   = $false
        }
    }
}

function Update-LocTelemetry {
    try {
        $os = Update-LocTelemetryCore
        Update-LocTelemetryExtras -Os $os
        $script:LocTelemetry.Updated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $script:LocTelemetryLastUpdate = Get-Date
    }
    catch {
        Write-LocLog -Module "CORE" -Action "TaskRunner" -Level "WARN" -Message $_.Exception.Message
    }
}
