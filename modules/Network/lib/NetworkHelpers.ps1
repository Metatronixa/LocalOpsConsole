# Network helpers — hosts file + WINS/NetBIOS

function Get-LocHostsFilePath {
    return (Join-Path $env:SystemRoot "System32\drivers\etc\hosts")
}

function Get-LocHostsBackupPath {
    return (Join-Path $env:SystemRoot "System32\drivers\etc\hosts.bak.loc")
}

function Backup-LocHostsFile {
    $path = Get-LocHostsFilePath
    $bak = Get-LocHostsBackupPath
    if (Test-Path $path) {
        Copy-Item -LiteralPath $path -Destination $bak -Force -ErrorAction Stop
    }
    return $bak
}

function Parse-LocHostsFile {
    param([string]$Content)
    $rows = @()
    $lineNo = 0
    foreach ($raw in ($Content -split "`r?`n")) {
        $lineNo++
        $line = $raw
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $enabled = $true
        $work = $trimmed
        if ($work.StartsWith('#')) {
            $enabled = $false
            $work = $work.TrimStart('#').Trim()
            if ([string]::IsNullOrWhiteSpace($work)) { continue }
        }

        $comment = ""
        $hashIdx = $work.IndexOf('#')
        if ($hashIdx -ge 0) {
            $comment = $work.Substring($hashIdx + 1).Trim()
            $work = $work.Substring(0, $hashIdx).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($work)) { continue }

        $parts = @($work -split '\s+' | Where-Object { $_ })
        if ($parts.Count -lt 2) { continue }
        $ip = $parts[0]
        if ($ip -notmatch '^[\d.:a-fA-F]+$' -and $ip -ne '::1') { continue }
        $names = @($parts | Select-Object -Skip 1)
        $rows += [PSCustomObject]@{
            LineNumber = $lineNo
            Enabled    = $enabled
            IP         = $ip
            Hostnames  = ($names -join ' ')
            Names      = @($names)
            Comment    = $comment
            Raw        = $raw
        }
    }
    return @($rows)
}

function Format-DnsList {
    param($List)
    if (-not $List) { return "-" }
    $arr = @($List)
    if ($arr.Count -eq 0) { return "-" }
    return ($arr -join ", ")
}

function Get-LocNetbiosModeLabel {
    param($Value)
    # TcpipNetbiosOptions: 0=Use DHCP/NetBIOS from DHCP, 1=Enable, 2=Disable
    switch ([string]$Value) {
        "0" { return "Default (DHCP)" }
        "1" { return "Enabled" }
        "2" { return "Disabled" }
        default { return if ($null -ne $Value) { [string]$Value } else { "Unknown" } }
    }
}
