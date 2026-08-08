# core/LicenseManager.ps1 - Edition / SKU / license status facade
# Public MIT tree: Community is always valid (no hard gate).
# Paid fork later: verify offline signed license blob with embedded public key.

$script:LocLicenseStatus = $null

function Get-LocLicenseDataDir {
    $root = Get-LocRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
    return (Join-Path $root "data\license")
}

function Get-LocLicenseFilePath {
    $dir = Get-LocLicenseDataDir
    if (-not $dir) { return $null }
    return (Join-Path $dir "license.json")
}

function Resolve-LocProductMode {
    param([object]$Settings = $null)
    if ($null -eq $Settings) { $Settings = Get-LocSettings }
    $mode = "desktop"
    if ($Settings -and $Settings.PSObject.Properties['productMode'] -and -not [string]::IsNullOrWhiteSpace([string]$Settings.productMode)) {
        $mode = ([string]$Settings.productMode).Trim().ToLowerInvariant()
    }
    if ($mode -notin @("desktop", "appliance")) { $mode = "desktop" }
    return $mode
}

function New-LocCommunityLicenseStatus {
    param(
        [string]$ProductMode = "desktop",
        [string]$Message = "Community edition (MIT) - ungated"
    )
    $mode = $ProductMode
    $msg = $Message
    return [PSCustomObject]@{
        Valid       = $true
        Edition     = "Community"
        Sku         = "community"
        ProductMode = $mode
        LicensedTo  = $null
        ExpiresAt   = $null
        AgentLimit  = $null
        Source      = "community"
        Message     = $msg
    }
}

function Read-LocLicenseBlob {
    # Prefer file; settings.licenseKey is a fallback string (never returned raw via API).
    $path = Get-LocLicenseFilePath
    if ($path -and (Test-Path -LiteralPath $path)) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                return [PSCustomObject]@{
                    Source = "file"
                    Path   = $path
                    Raw    = $raw.Trim()
                    Object = ($raw | ConvertFrom-Json -ErrorAction SilentlyContinue)
                }
            }
        }
        catch {
            return [PSCustomObject]@{
                Source = "file"
                Path   = $path
                Raw    = $null
                Object = $null
                Error  = $_.Exception.Message
            }
        }
    }

    $s = Get-LocSettings
    if ($s -and $s.PSObject.Properties['licenseKey'] -and -not [string]::IsNullOrWhiteSpace([string]$s.licenseKey)) {
        $key = ([string]$s.licenseKey).Trim()
        $obj = $null
        try { $obj = $key | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $obj = $null }
        return [PSCustomObject]@{
            Source = "settings"
            Path   = $null
            Raw    = $key
            Object = $obj
        }
    }
    return $null
}

function Initialize-LocLicense {
    param(
        [ValidateSet("desktop", "appliance")]
        [string]$ProductModeOverride = ""
    )

    $settings = Get-LocSettings
    $productMode = if (-not [string]::IsNullOrWhiteSpace($ProductModeOverride)) {
        $ProductModeOverride.ToLowerInvariant()
    }
    else {
        Resolve-LocProductMode -Settings $settings
    }

    # Ensure license directory exists for future paid installs (file stays gitignored).
    $dir = Get-LocLicenseDataDir
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        catch { Write-Debug $_.Exception.Message }
    }

    $blob = Read-LocLicenseBlob
    if ($null -eq $blob -or [string]::IsNullOrWhiteSpace([string]$blob.Raw)) {
        $script:LocLicenseStatus = New-LocCommunityLicenseStatus -ProductMode $productMode
        return $script:LocLicenseStatus
    }

    # Public tree: presence of a license file does not gate; still surface parsed metadata for hooks.
    # Commercial fork replaces this block with signature verification + hard Valid=$false on failure.
    $obj = $blob.Object
    $edition = "Community"
    $sku = "community"
    $licensedTo = $null
    $expiresAt = $null
    $agentLimit = $null
    $msg = "License file present; Community path ignores signature (MIT ungated)"

    if ($obj) {
        if ($obj.PSObject.Properties['edition'] -and -not [string]::IsNullOrWhiteSpace([string]$obj.edition)) {
            $edition = [string]$obj.edition
        }
        if ($obj.PSObject.Properties['sku'] -and -not [string]::IsNullOrWhiteSpace([string]$obj.sku)) {
            $sku = [string]$obj.sku
        }
        if ($obj.PSObject.Properties['licensedTo']) { $licensedTo = [string]$obj.licensedTo }
        if ($obj.PSObject.Properties['expiresAt']) { $expiresAt = [string]$obj.expiresAt }
        if ($obj.PSObject.Properties['agentLimit'] -and $null -ne $obj.agentLimit) {
            try { $agentLimit = [int]$obj.agentLimit } catch { $agentLimit = $null }
        }
    }
    elseif ($blob.Error) {
        $msg = "License file unreadable; falling back to Community - $($blob.Error)"
    }

    $script:LocLicenseStatus = [PSCustomObject]@{
        Valid       = $true
        Edition     = $edition
        Sku         = $sku
        ProductMode = $productMode
        LicensedTo  = $licensedTo
        ExpiresAt   = $expiresAt
        AgentLimit  = $agentLimit
        Source      = if ($blob.Source) { [string]$blob.Source } else { "community" }
        Message     = $msg
    }
    return $script:LocLicenseStatus
}

function Get-LocLicenseStatus {
    if ($null -eq $script:LocLicenseStatus) {
        return Initialize-LocLicense
    }
    return $script:LocLicenseStatus
}

function Get-LocLicenseSummary {
    # Safe for settings/API - never includes raw key material.
    $st = Get-LocLicenseStatus
    return [PSCustomObject]@{
        Valid       = [bool]$st.Valid
        Edition     = [string]$st.Edition
        Sku         = [string]$st.Sku
        ProductMode = [string]$st.ProductMode
        LicensedTo  = $st.LicensedTo
        ExpiresAt   = $st.ExpiresAt
        AgentLimit  = $st.AgentLimit
        Source      = [string]$st.Source
        Message     = [string]$st.Message
    }
}

function Test-LocEdition {
    param(
        [Parameter(Mandatory)]
        [string]$RequiredEdition
    )
    $need = $RequiredEdition.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($need) -or $need -eq "community") { return $true }

    $st = Get-LocLicenseStatus
    # MIT Community path: all editions allowed so hooks stay dormant.
    if ([string]$st.Edition -eq "Community" -or [string]$st.Sku -eq "community") { return $true }

    $have = ([string]$st.Edition).Trim().ToLowerInvariant()
    $haveSku = ([string]$st.Sku).Trim().ToLowerInvariant()
    return ($have -eq $need -or $haveSku -eq $need)
}

function Assert-LocFeature {
    param(
        [Parameter(Mandatory)]
        [string]$Feature
    )
    # Placeholder for paid-fork feature flags. Community always allows.
    if ([string]::IsNullOrWhiteSpace($Feature)) { return $true }
    $st = Get-LocLicenseStatus
    if ([bool]$st.Valid) { return $true }
    return $false
}

function Test-LocApplianceMode {
    $st = Get-LocLicenseStatus
    return ([string]$st.ProductMode -eq "appliance")
}
