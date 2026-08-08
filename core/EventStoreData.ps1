# core/EventStoreData.ps1 - Events, alerts, suppressions, and incident files

function Save-LocRecentEvents {
    param([object[]]$Events, [int]$MaxKeep = 300)
    $list = @($Events | Select-Object -First $MaxKeep)
    Invoke-LocEventFileLock -Name "events" -Action {
        Write-LocEventJson -FileName "events.json" -Data @($list)
    }
}

function Get-LocStoredEvents {
    param([int]$Max = 200)
    $take = $Max
    return Invoke-LocEventFileLock -Name "events" -Action {
        $raw = Read-LocEventJson -FileName "events.json" -Default @()
        return @($raw | Select-Object -First $take)
    }
}

function Get-LocStoredAlerts {
    return Invoke-LocEventFileLock -Name "alerts" -Action {
        return @(Read-LocEventJson -FileName "alerts.json" -Default @())
    }
}

function Save-LocStoredAlerts {
    param([object[]]$Alerts)
    $payload = @($Alerts)
    Invoke-LocEventFileLock -Name "alerts" -Action {
        Write-LocEventJson -FileName "alerts.json" -Data @($payload)
    }
}

function Get-LocSuppressions {
    return Invoke-LocEventFileLock -Name "suppressions" -Action {
        return @(Read-LocEventJson -FileName "suppressions.json" -Default @())
    }
}

function Save-LocSuppressions {
    param([object[]]$Items)
    $payload = @($Items)
    Invoke-LocEventFileLock -Name "suppressions" -Action {
        Write-LocEventJson -FileName "suppressions.json" -Data @($payload)
    }
}

function Write-LocIncidentFile {
    param(
        [Parameter(Mandatory)][object]$Incident,
        [ValidateSet("active", "resolved", "archive")]
        [string]$StatusFolder = "active"
    )
    $dir = Join-Path (Get-LocIncidentDir) $StatusFolder
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $id = [string]$Incident.Id
    $path = Join-Path $dir "$id.json"
    $tmp = "$path.tmp"
    $json = $Incident | ConvertTo-Json -Depth 14 -Compress:$false
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path $path) { Remove-Item $path -Force }
    Move-Item $tmp $path -Force
}

function Remove-LocIncidentFile {
    param(
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet("active", "resolved", "archive")]
        [string]$StatusFolder
    )
    $path = Join-Path (Join-Path (Get-LocIncidentDir) $StatusFolder) "$Id.json"
    if (Test-Path $path) { Remove-Item $path -Force -ErrorAction SilentlyContinue }
}

function Read-LocIncidentFile {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $raw = Get-Content $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }
    catch { return $null }
}

function Get-LocIncidentFiles {
    param([ValidateSet("active", "resolved", "archive", "all")][string]$Status = "all")
    $folders = if ($Status -eq "all") { @("active", "resolved", "archive") } else { @($Status) }
    $items = @()
    foreach ($f in $folders) {
        $dir = Join-Path (Get-LocIncidentDir) $f
        if (-not (Test-Path $dir)) { continue }
        Get-ChildItem -Path $dir -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
            $inc = Read-LocIncidentFile -Path $_.FullName
            if ($inc) { $items += $inc }
        }
    }
    return @($items | Sort-Object { $_.UpdatedAt } -Descending)
}
