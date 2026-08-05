try {
    $catalog = Get-LocConfigCatalog
    $settings = @()
    foreach ($def in @($catalog.settings)) {
        $raw = Get-LocConfigSettingValue -Def $def
        $settings += (New-LocConfigSettingCard -Def $def -CurrentRaw $raw)
    }

    $categories = @()
    foreach ($cat in @($catalog.categories)) {
        $enabled = $true
        if ($null -ne $cat.PSObject.Properties['enabled']) {
            $enabled = [bool]$cat.enabled
        }
        $catSettings = @($settings | Where-Object { $_.Category -eq $cat.id })
        $categories += [PSCustomObject]@{
            Id          = [string]$cat.id
            Name        = [string]$cat.name
            Description = [string]$cat.description
            Enabled     = $enabled
            Settings    = @($catSettings)
        }
    }

    return New-ApiResult -Success $true -Message ("{0} setting(s) in catalog" -f $settings.Count) -Data ([PSCustomObject]@{
        Categories = @($categories)
        Settings   = @($settings)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
