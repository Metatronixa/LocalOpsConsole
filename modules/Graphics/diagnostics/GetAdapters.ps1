try {
    $adapters = @()
    Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        $name = [string]$_.Name
        $pnp = [string]$_.PNPDeviceID
        $vendor = "Other"
        if ($name -match 'NVIDIA|GeForce|Quadro|RTX|GTX' -or $pnp -match 'VEN_10DE') { $vendor = "NVIDIA" }
        elseif ($name -match 'AMD|Radeon|ATI' -or $pnp -match 'VEN_1002') { $vendor = "AMD" }
        elseif ($name -match 'Intel' -or $pnp -match 'VEN_8086') { $vendor = "Intel" }

        $updateUrl = switch ($vendor) {
            "NVIDIA" { "https://www.nvidia.com/Download/index.aspx" }
            "AMD"    { "https://www.amd.com/en/support" }
            "Intel"  { "https://www.intel.com/content/www/us/en/download-center/home.html" }
            default  { "https://www.google.com/search?q=" + [uri]::EscapeDataString("$name graphics driver download") }
        }

        $driverDate = $null
        if ($_.DriverDate) {
            try { $driverDate = ([DateTime]$_.DriverDate).ToString("yyyy-MM-dd") } catch { $driverDate = [string]$_.DriverDate }
        }

        $ramGB = $null
        if ($_.AdapterRAM -and $_.AdapterRAM -gt 0 -and $_.AdapterRAM -lt [uint64]::MaxValue) {
            $ramGB = [math]::Round(($_.AdapterRAM / 1GB), 2)
        }

        $adapters += [PSCustomObject]@{
            Name          = $name
            Vendor        = $vendor
            DriverVersion = [string]$_.DriverVersion
            DriverDate    = $driverDate
            Status        = [string]$_.Status
            VideoMode     = [string]$_.VideoModeDescription
            AdapterRAMGB  = $ramGB
            PNPDeviceID   = $pnp
            UpdateUrl     = $updateUrl
        }
    }

    return New-ApiResult -Success $true -Message ("{0} graphics adapter(s)" -f $adapters.Count) -Data ([PSCustomObject]@{
        Adapters = @($adapters)
        Tip      = "Use OpenVendorUpdatePage or open UpdateUrl in a browser to get the latest driver."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
