# InternetSlowHelpers.ps1
# Fast, best-effort networking checks used by the InternetIsSlow diagnostic engine.

function Get-LocFirstIPv4DefaultGateway {
    try {
        # WMI is generally available without importing NetTCPIP/NetAdapter-heavy modules.
        $cfgs = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue
        foreach ($cfg in $cfgs) {
            $gws = @($cfg.DefaultIPGateway | Where-Object { $_ -and ($_ -match '^\d+\.\d+\.\d+\.\d+$') })
            if ($gws.Count -gt 0) { return [string]$gws[0] }
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-LocPrimaryIPv4InterfaceInfo {
    try {
        # NetIPInterface is usually fast enough. If it fails, we return best-effort empties.
        $iface = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceOperationalStatus -ne 'Unknown' } |
            Sort-Object InterfaceMetric |
            Select-Object -First 1

        if (-not $iface) { return $null }
        return [PSCustomObject]@{
            InterfaceAlias = [string]$iface.InterfaceAlias
            InterfaceIndex = [int]$iface.InterfaceIndex
            NlMtu           = $iface.NlMtu
            InterfaceMetric= $iface.InterfaceMetric
        }
    }
    catch {
        return $null
    }
}

function Get-LocPrimaryAdapterSpeed {
    try {
        $na = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } |
            Select-Object -First 1
        if (-not $na) { return $null }
        return [PSCustomObject]@{
            Name       = [string]$na.Name
            Status     = [string]$na.Status
            LinkSpeed  = [string]$na.LinkSpeed
            MacAddress = [string]$na.MacAddress
        }
    }
    catch {
        return $null
    }
}

function Invoke-LocDnsLookup {
    param(
        [string]$HostName = "google.com",
        [int]$TimeoutSec = 6
    )

    try {
        # Reuse tools' timeout-safe command runner
        $r = Invoke-ToolCommand -FilePath "nslookup.exe" -ArgumentList @($HostName) -TimeoutSec $TimeoutSec
        $success = ($r.ExitCode -eq 0 -and ($r.Output -match "(?i)\\bAddress\\b\\s*:"))
        return [PSCustomObject]@{
            TargetHost = $HostName
            Success     = $success
            ExitCode    = $r.ExitCode
            $snippetLines = @($r.Output -split "\r?\n" | Select-Object -First 12)
            OutputSnippet = ($snippetLines -join "`n")
        }
    }
    catch {
        return [PSCustomObject]@{
            TargetHost = $HostName
            Success     = $false
            ExitCode    = -1
            OutputSnippet = $_.Exception.Message
        }
    }
}

function Invoke-LocPingStats {
    param(
        [string]$Target,
        [int]$Count = 4
    )

    try {
        # Test-Connection returns only successful replies; packet loss is computed from count.
        $start = Get-Date
        $results = Test-Connection -ComputerName $Target -Count $Count -ErrorAction SilentlyContinue
        $elapsedMs = ([datetime]::Now - $start).TotalMilliseconds

        $rows = @($results | ForEach-Object {
            [PSCustomObject]@{
                Address    = $_.Address
                ResponseMs = $_.ResponseTime
                Status     = "Success"
            }
        })

        $successCount = $rows.Count
        $lossPct = if ($Count -gt 0) { [math]::Round((($Count - $successCount) / $Count) * 100, 0) } else { 0 }
        $avg = if ($rows.Count -gt 0) { [math]::Round(($rows | Measure-Object ResponseMs -Average).Average, 1) } else { 0 }

        return [PSCustomObject]@{
            Target      = $Target
            Count       = $Count
            SuccessCount= $successCount
            LossPct     = $lossPct
            AvgMs       = $avg
            ElapsedMs   = [int][math]::Round($elapsedMs, 0)
            Results     = $rows
        }
    }
    catch {
        return [PSCustomObject]@{
            Target       = $Target
            Count        = $Count
            SuccessCount = 0
            LossPct      = 100
            AvgMs        = 0
            ElapsedMs    = 0
            Results      = @()
        }
    }
}

function Invoke-LocTcpGlobals {
    param([int]$TimeoutSec = 6)
    try {
        $r = Invoke-ToolCommand -FilePath "netsh.exe" -ArgumentList @("interface", "tcp", "show", "global") -TimeoutSec $TimeoutSec
        return [PSCustomObject]@{
            Success  = ($r.ExitCode -eq 0 -and $r.Output -and $r.Output.Trim().Length -gt 0)
            ExitCode = $r.ExitCode
            $snippetLines = @($r.Output -split "\r?\n" | Select-Object -First 20)
            OutputSnippet = ($snippetLines -join "`n")
        }
    }
    catch {
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = -1
            OutputSnippet = $_.Exception.Message
        }
    }
}

function Invoke-LocFirewallProfileSummary {
    try {
        $profiles = @('Domain', 'Private', 'Public')
        $out = @()
        $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        foreach ($p in $profiles) {
            $item = $fw | Where-Object { $_.Name -eq $p } | Select-Object -First 1
            if ($item) {
                $out += [PSCustomObject]@{ Profile=$p; Enabled=[bool]$item.Enabled; DefaultInboundAction=$item.DefaultInboundAction }
            }
        }
        return $out
    }
    catch {
        return @()
    }
}

