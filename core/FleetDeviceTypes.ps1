# core/FleetDeviceTypes.ps1 - LAN discovery and device-type overrides

function Get-LocLanDiscoveryRows {
    $rows = @()
    try {
        if (Get-Command Invoke-LocModuleAction -ErrorAction SilentlyContinue) {
            $disc = Invoke-LocModuleAction -ModuleId "remote" -Kind "diagnostics" -ActionName "DiscoverComputers" -ForceRefresh $true
            if ($disc -and $disc.Success -and $disc.Data) {
                return @($disc.Data)
            }
        }
    }
    catch { Write-Debug $_.Exception.Message }

    try {
        Import-Module NetTCPIP -ErrorAction SilentlyContinue | Out-Null
        Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and
                $_.IPAddress -notmatch '^(127\.|0\.|224\.|239\.|255\.)' -and
                $_.State -ne 'Unreachable'
            } |
            ForEach-Object {
                $rows += [PSCustomObject]@{
                    Name          = $_.IPAddress
                    IPAddress     = $_.IPAddress
                    MACAddress    = $_.LinkLayerAddress
                    Online        = ($_.State -eq 'Reachable' -or $_.State -eq 'Permanent')
                    NeighborState = [string]$_.State
                    Source        = "ARP/Neighbor"
                }
            }
    }
    catch { Write-Debug $_.Exception.Message }
    return @($rows)
}

function Get-LocDeviceTypeOverridesPath {
    return (Join-Path (Get-LocRoot) "data\fleet\device-types.json")
}

function Get-LocDeviceTypeOverrides {
    $path = Get-LocDeviceTypeOverridesPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path $path)) { return [PSCustomObject]@{} }
    try {
        $raw = Get-Content $path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{} }
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { return [PSCustomObject]@{} }
        return $obj
    }
    catch {
        Write-LocLog -Module "FLEET" -Action "DeviceTypes" -Level "WARN" -Message $_.Exception.Message
        return [PSCustomObject]@{}
    }
}

function Save-LocDeviceTypeOverrides {
    param([object]$Prefs)
    $path = Get-LocDeviceTypeOverridesPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    try {
        $json = ($Prefs | ConvertTo-Json -Depth 6 -Compress:$false)
        $tmp = "$path.tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path $path) { Remove-Item $path -Force }
        Move-Item $tmp $path -Force
        return $true
    }
    catch {
        Write-LocLog -Module "FLEET" -Action "DeviceTypes" -Level "ERROR" -Message $_.Exception.Message
        return $false
    }
}

function Normalize-LocMacKey {
    param([string]$Mac)
    if ([string]::IsNullOrWhiteSpace($Mac)) { return "" }
    return (($Mac -replace '[^0-9A-Fa-f]', '').ToLowerInvariant())
}

function Resolve-LocDeviceTypeInferred {
    param(
        [string]$Kind,
        [string]$Label,
        [string]$IPv4
    )
    $k = if ($Kind) { $Kind.ToLowerInvariant() } else { "" }
    if ($k -eq "gateway") { return "router" }
    if ($k -eq "console" -or $k -eq "agent") { return "pc" }

    $hay = ("{0} {1}" -f $Label, $IPv4).ToLowerInvariant()
    if ($hay -match 'playstation|\bps5\b|\bps4\b|\bps[345]\b') { return "playstation" }
    if ($hay -match 'xbox|xboxone|series[- ]?[xs]\b') { return "xbox" }
    if ($hay -match '\bnas\b|synology|qnap|truenas|freenas|unraid|netgear.?ready') { return "nas" }
    if ($hay -match 'switch|\bsw[-_]|nexus|catalyst|unifi[- ]?sw|procurve') { return "switch" }
    if ($hay -match 'router|gateway|\bfw[-_]|firewall|mikrotik|edgeos|opnsense|pfsense|asus[-_]|tplink|tp[- ]?link|netgear|access.?point|\bap[-_]|unifi[- ]?ap|\beap\b') {
        return "router"
    }
    return "unknown"
}

function Get-LocDeviceTypeOverrideForNode {
    param(
        [object]$Overrides,
        [string]$NodeId,
        [string]$MacAddress,
        [string]$IPv4
    )
    if (-not $Overrides) { return $null }
    $keys = @()
    $macKey = Normalize-LocMacKey $MacAddress
    if ($macKey) { $keys += "mac:$macKey" }
    if ($NodeId) { $keys += "id:$NodeId" }
    if ($IPv4) { $keys += "ip:$IPv4" }
    foreach ($key in $keys) {
        if ($Overrides.PSObject.Properties[$key]) {
            $entry = $Overrides.$key
            if ($null -eq $entry) { continue }
            if ($entry -is [string]) { return [string]$entry }
            if ($entry.PSObject.Properties['deviceType']) { return [string]$entry.deviceType }
            if ($entry -is [hashtable] -and $entry.ContainsKey('deviceType')) { return [string]$entry['deviceType'] }
        }
    }
    return $null
}

function Set-LocFleetDeviceType {
    param(
        [Parameter(Mandatory)][string]$NodeId,
        [Parameter(Mandatory)][string]$DeviceType,
        [string]$MacAddress = "",
        [string]$IPv4 = "",
        [string]$Operator = "operator"
    )
    $allowed = @('pc', 'router', 'switch', 'nas', 'playstation', 'xbox', 'unknown', 'auto')
    $dt = $DeviceType.Trim().ToLowerInvariant()
    if ($allowed -notcontains $dt) {
        return New-ApiResult -Success $false -Message "Invalid deviceType" -StatusCode 400
    }

    $prefs = Get-LocDeviceTypeOverrides
    if (-not $prefs) { $prefs = [PSCustomObject]@{} }

    $keys = New-Object System.Collections.ArrayList
    $macKey = Normalize-LocMacKey $MacAddress
    if ($macKey) { [void]$keys.Add("mac:$macKey") }
    if ($NodeId) { [void]$keys.Add("id:$NodeId") }
    if ($IPv4) { [void]$keys.Add("ip:$IPv4") }
    if ($keys.Count -eq 0) {
        return New-ApiResult -Success $false -Message "NodeId required" -StatusCode 400
    }

    if ($dt -eq "auto") {
        foreach ($key in $keys) {
            if ($prefs.PSObject.Properties[$key]) {
                $prefs.PSObject.Properties.Remove($key)
            }
        }
    }
    else {
        $entry = [PSCustomObject]@{
            deviceType = $dt
            nodeId     = $NodeId
            updatedAt  = (Get-Date).ToUniversalTime().ToString('o')
            updatedBy  = $Operator
        }
        foreach ($key in $keys) {
            $prefs | Add-Member -NotePropertyName $key -NotePropertyValue $entry -Force
        }
    }

    if (-not (Save-LocDeviceTypeOverrides -Prefs $prefs)) {
        return New-ApiResult -Success $false -Message "Failed to save device type" -StatusCode 500
    }

    return New-ApiResult -Success $true -Message "Device type saved" -Data ([PSCustomObject]@{
        NodeId     = $NodeId
        DeviceType = $(if ($dt -eq 'auto') { $null } else { $dt })
        Cleared    = ($dt -eq 'auto')
    })
}

