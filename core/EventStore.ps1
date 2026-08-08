# core/EventStore.ps1 - JSON persistence primitives for Event Intelligence

$script:LocEventDir = $null
$script:LocIncidentDir = $null
$script:LocEventLock = [System.Collections.Hashtable]::Synchronized(@{})

function Get-LocEventDir {
    if (-not $script:LocEventDir) {
        $script:LocEventDir = Join-Path (Get-LocRoot) "data\events"
    }
    return $script:LocEventDir
}

function Get-LocIncidentDir {
    if (-not $script:LocIncidentDir) {
        $script:LocIncidentDir = Join-Path (Get-LocRoot) "data\incidents"
    }
    return $script:LocIncidentDir
}

function Initialize-LocEventStore {
    $eventDir = Get-LocEventDir
    $incDir = Get-LocIncidentDir
    foreach ($d in @(
            $eventDir,
            (Join-Path $incDir "active"),
            (Join-Path $incDir "resolved"),
            (Join-Path $incDir "archive")
        )) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    foreach ($name in @("events.json", "alerts.json", "suppressions.json", "audit.jsonl", "prefs.json")) {
        $path = Join-Path $eventDir $name
        if (-not (Test-Path $path)) {
            if ($name -eq "audit.jsonl") {
                [System.IO.File]::WriteAllText($path, "", [System.Text.UTF8Encoding]::new($false))
            }
            elseif ($name -eq "prefs.json") {
                Write-LocEventJson -FileName "prefs.json" -Data @{ Updated = $null }
            }
            else {
                Write-LocEventJson -FileName $name -Data @()
            }
        }
    }
}

function Invoke-LocEventFileLock {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    $lockObj = $script:LocEventLock
    if (-not $lockObj.ContainsKey($Name)) {
        $lockObj[$Name] = New-Object System.Object
    }
    [System.Threading.Monitor]::Enter($lockObj[$Name])
    try {
        return & $Action
    }
    finally {
        [System.Threading.Monitor]::Exit($lockObj[$Name])
    }
}

function Read-LocEventJson {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [object]$Default = $null
    )
    $path = Join-Path (Get-LocEventDir) $FileName
    if (-not (Test-Path $path)) { return $Default }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-LocLog -Module "EVENTINTEL" -Action "ReadJson" -Level "ERROR" -Message "Failed reading $FileName : $($_.Exception.Message)"
        return $Default
    }
}

function Write-LocEventJson {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][object]$Data
    )
    $dir = Get-LocEventDir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Join-Path $dir $FileName
    $tmp = "$path.tmp"
    if ($null -eq $Data) { $Data = @() }
    # Always emit a JSON array for list-shaped payloads (PS ConvertTo-Json collapses single-item arrays)
    $asList = $Data -is [System.Collections.IEnumerable] -and -not ($Data -is [string]) -and -not ($Data -is [hashtable]) -and -not ($Data -is [System.Collections.IDictionary])
    if ($asList) {
        $items = @($Data)
        if ($items.Count -eq 0) {
            $json = "[]"
        }
        elseif ($items.Count -eq 1) {
            $json = "[" + ($items[0] | ConvertTo-Json -Depth 14 -Compress:$false) + "]"
        }
        else {
            $json = $items | ConvertTo-Json -Depth 14 -Compress:$false
            if (-not $json.TrimStart().StartsWith("[")) { $json = "[$json]" }
        }
    }
    else {
        $json = $Data | ConvertTo-Json -Depth 14 -Compress:$false
    }
    if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path $path) { Remove-Item $path -Force }
    Move-Item $tmp $path -Force
}

function Add-LocEventAudit {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Detail = "",
        [string]$Operator = "system",
        [hashtable]$Data = @{}
    )
    $path = Join-Path (Get-LocEventDir) "audit.jsonl"
    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        Action    = $Action
        Operator  = $Operator
        Detail    = $Detail
        Data      = $Data
    }
    $line = ($entry | ConvertTo-Json -Depth 8 -Compress)
    Invoke-LocEventFileLock -Name "audit" -Action {
        [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
}

function New-LocNormalizedEvent {
    param(
        [string]$Source,
        [int]$EventID = 0,
        [ValidateSet("Critical", "Warning", "Information")]
        [string]$Severity = "Information",
        [string]$Category = "system",
        [string]$Message = "",
        [hashtable]$Data = @{},
        [string]$Computer = $env:COMPUTERNAME,
        [datetime]$Timestamp = (Get-Date)
    )
    return [PSCustomObject]@{
        Id        = [guid]::NewGuid().ToString()
        Source    = $Source
        EventID   = $EventID
        Severity  = $Severity
        Computer  = $Computer
        Timestamp = $Timestamp.ToUniversalTime().ToString("o")
        Category  = $Category
        Message   = $Message
        Data      = $Data
    }
}
