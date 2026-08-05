# Configuration helpers — catalog load + registry / provider get/set

function Get-LocConfigCatalogPath {
    return Join-Path $PSScriptRoot "settings-catalog.json"
}

function Get-LocConfigCatalog {
    $path = Get-LocConfigCatalogPath
    if (-not (Test-Path $path)) {
        throw "Configuration catalog not found: $path"
    }
    $raw = Get-Content -Path $path -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Get-LocConfigSettingDef {
    param([Parameter(Mandatory)][string]$SettingId)
    $catalog = Get-LocConfigCatalog
    $def = @($catalog.settings) | Where-Object { $_.id -eq $SettingId } | Select-Object -First 1
    if (-not $def) {
        throw "Unknown setting id: $SettingId"
    }
    return $def
}

function Get-LocConfigRegistryPath {
    param($Def)
    $hive = [string]$Def.hive
    $sub = [string]$Def.path
    switch ($hive.ToUpper()) {
        "HKCU" { return "HKCU:\$sub" }
        "HKLM" { return "HKLM:\$sub" }
        default { throw "Unsupported hive: $hive" }
    }
}

function Format-LocConfigDisplayValue {
    param($Def, $RawValue)
    if ($null -eq $RawValue -or ([string]$RawValue).Length -eq 0) { return "Not set" }
    $key = [string]$RawValue
    if ($Def.labels) {
        $prop = $Def.labels.PSObject.Properties | Where-Object { $_.Name -eq $key } | Select-Object -First 1
        if ($prop) { return [string]$prop.Value }
    }
    return [string]$RawValue
}

function Get-LocConfigRegistryValue {
    param($Def)
    $regPath = Get-LocConfigRegistryPath -Def $Def
    $name = [string]$Def.valueName
    if (-not (Test-Path $regPath)) {
        return $null
    }
    try {
        $item = Get-ItemProperty -Path $regPath -Name $name -ErrorAction Stop
        return $item.$name
    }
    catch {
        return $null
    }
}

function Set-LocConfigRegistryValue {
    param($Def, $Value)
    $regPath = Get-LocConfigRegistryPath -Def $Def
    $name = [string]$Def.valueName
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    $type = [string]$Def.valueType
    if ([string]::IsNullOrWhiteSpace($type)) { $type = "DWord" }

    $typed = $Value
    if ($type -eq "DWord") {
        $typed = [int]$Value
    }
    else {
        $typed = [string]$Value
    }

    New-ItemProperty -Path $regPath -Name $name -Value $typed -PropertyType $type -Force | Out-Null
    return Get-LocConfigRegistryValue -Def $Def
}

function Get-LocConfigProvider {
    param($Def)
    if ($Def.PSObject.Properties['provider'] -and $Def.provider) {
        return [string]$Def.provider
    }
    return "registry"
}

function Get-LocConfigSettingValue {
    param($Def)
    $provider = Get-LocConfigProvider -Def $Def
    switch ($provider) {
        "powercfgHibernate" {
            try {
                $out = & powercfg.exe /a 2>&1 | Out-String
                if ($out -match '(?i)Hibernation has not been enabled') { return 0 }
                if ($out -match '(?i)Hibernate') { return 1 }
                $reg = Get-LocConfigRegistryValue -Def $Def
                if ($null -ne $reg) { return [int]$reg }
                return $null
            }
            catch { return $null }
        }
        "powercfgSleepAc" {
            try {
                $scheme = (& powercfg.exe /getactivescheme 2>&1 | Out-String)
                if ($scheme -match '([0-9a-fA-F-]{36})') {
                    $guid = $Matches[1]
                    # Subgroup: sleep, Setting: sleep after — query AC index (seconds)
                    $q = & powercfg.exe /q $guid SUB_SLEEP STANDBYIDLE 2>&1 | Out-String
                    if ($q -match '(?i)Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
                        $sec = [Convert]::ToInt32($Matches[1], 16)
                        return [int][math]::Round($sec / 60.0)
                    }
                }
                return $null
            }
            catch { return $null }
        }
        "powercfgUsbSuspend" {
            try {
                $scheme = (& powercfg.exe /getactivescheme 2>&1 | Out-String)
                if ($scheme -match '([0-9a-fA-F-]{36})') {
                    $guid = $Matches[1]
                    $q = & powercfg.exe /q $guid 2c67a866-5f66-4dcb-ae1b-8e5c3f1b3c2f 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 2>&1 | Out-String
                    # USB selective suspend setting GUID commonly 48e6b7a6-...
                    if ($q -match '(?i)Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
                        $idx = [Convert]::ToInt32($Matches[1], 16)
                        # 0 = disabled suspend, 1 = enabled — map to our labels where 1 = suspend disabled
                        if ($idx -eq 0) { return 1 } else { return 0 }
                    }
                }
                return Get-LocConfigRegistryValue -Def $Def
            }
            catch { return Get-LocConfigRegistryValue -Def $Def }
        }
        "defenderRealtime" {
            try {
                $pref = Get-MpPreference -ErrorAction Stop
                if ($pref.DisableRealtimeMonitoring) { return 1 } else { return 0 }
            }
            catch {
                return Get-LocConfigRegistryValue -Def $Def
            }
        }
        "firewallPrivate" {
            try {
                $p = Get-NetFirewallProfile -Name Private -ErrorAction Stop
                if ($p.Enabled) { return 1 } else { return 0 }
            }
            catch {
                return Get-LocConfigRegistryValue -Def $Def
            }
        }
        default {
            return Get-LocConfigRegistryValue -Def $Def
        }
    }
}

function Set-LocConfigSettingValue {
    param($Def, $Value)
    $provider = Get-LocConfigProvider -Def $Def
    switch ($provider) {
        "powercfgHibernate" {
            $on = ([string]$Value -eq "1" -or $Value -eq 1)
            if ($on) {
                & powercfg.exe /hibernate on 2>&1 | Out-Null
            }
            else {
                & powercfg.exe /hibernate off 2>&1 | Out-Null
            }
            return Get-LocConfigSettingValue -Def $Def
        }
        "powercfgSleepAc" {
            $minutes = [int]$Value
            $sec = $minutes * 60
            & powercfg.exe /change standby-timeout-ac $minutes 2>&1 | Out-Null
            return Get-LocConfigSettingValue -Def $Def
        }
        "powercfgUsbSuspend" {
            # Value 1 = suspend disabled (recommended), 0 = suspend allowed
            $scheme = (& powercfg.exe /getactivescheme 2>&1 | Out-String)
            if ($scheme -match '([0-9a-fA-F-]{36})') {
                $guid = $Matches[1]
                $settingVal = if ([string]$Value -eq "1" -or $Value -eq 1) { 0 } else { 1 }
                & powercfg.exe /setacvalueindex $guid 2c67a866-5f66-4dcb-ae1b-8e5c3f1b3c2f 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 $settingVal 2>&1 | Out-Null
                & powercfg.exe /setactive $guid 2>&1 | Out-Null
            }
            return Get-LocConfigSettingValue -Def $Def
        }
        "defenderRealtime" {
            $disable = ([string]$Value -eq "1" -or $Value -eq 1)
            Set-MpPreference -DisableRealtimeMonitoring:$disable -ErrorAction Stop
            return Get-LocConfigSettingValue -Def $Def
        }
        "firewallPrivate" {
            $enable = -not ([string]$Value -eq "0" -or $Value -eq 0)
            Set-NetFirewallProfile -Profile Private -Enabled $enable -ErrorAction Stop
            return Get-LocConfigSettingValue -Def $Def
        }
        default {
            return Set-LocConfigRegistryValue -Def $Def -Value $Value
        }
    }
}

function Test-LocConfigReadOnly {
    param($Def)
    return ($Def.PSObject.Properties['readOnly'] -and [bool]$Def.readOnly)
}

function New-LocConfigSettingCard {
    param($Def, $CurrentRaw)
    $pathDisplay = ("{0}\{1}" -f $Def.hive, $Def.path)
    $rec = $Def.recommended
    $defVal = $Def.microsoftDefault
    $provider = Get-LocConfigProvider -Def $Def
    return [PSCustomObject]@{
        Id                      = [string]$Def.id
        Category                = [string]$Def.category
        Name                    = [string]$Def.name
        Description             = [string]$Def.description
        CurrentRaw              = $CurrentRaw
        Current                 = (Format-LocConfigDisplayValue -Def $Def -RawValue $CurrentRaw)
        RecommendedRaw          = $rec
        Recommended             = (Format-LocConfigDisplayValue -Def $Def -RawValue $rec)
        MicrosoftDefaultRaw     = $defVal
        MicrosoftDefault        = (Format-LocConfigDisplayValue -Def $Def -RawValue $defVal)
        Hive                    = [string]$Def.hive
        Path                    = $pathDisplay
        ValueName               = [string]$Def.valueName
        ValueType               = [string]$Def.valueType
        Provider                = $provider
        Risk                    = [string]$Def.risk
        RequiresRestart         = [bool]$Def.requiresRestart
        RequiresLogoff          = [bool]$Def.requiresLogoff
        RequiresExplorerRestart = [bool]$Def.requiresExplorerRestart
        RequiresAdmin           = [bool]$Def.requiresAdmin
        ReadOnly                = (Test-LocConfigReadOnly -Def $Def)
        MatchesRecommended      = ($null -ne $CurrentRaw -and [string]$CurrentRaw -eq [string]$rec)
        MatchesDefault          = ($null -ne $CurrentRaw -and [string]$CurrentRaw -eq [string]$defVal)
    }
}
