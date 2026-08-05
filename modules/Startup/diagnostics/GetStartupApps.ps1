try {
    $items = @()
    $runKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($key in $runKeys) {
        if (-not (Test-Path $key)) { continue }
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) { continue }
            $items += [PSCustomObject]@{
                Name    = $p.Name
                Command = [string]$p.Value
                Location= $key
                Source  = "Registry"
                Enabled = $true
            }
        }
    }

    $startupFolder = [Environment]::GetFolderPath("Startup")
    if (Test-Path $startupFolder) {
        Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | ForEach-Object {
            $items += [PSCustomObject]@{
                Name     = $_.Name
                Command  = $_.FullName
                Location = $startupFolder
                Source   = "StartupFolder"
                Enabled  = $true
            }
        }
    }

    return New-ApiResult -Success $true -Message ("{0} startup item(s)" -f $items.Count) -Data @($items)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
