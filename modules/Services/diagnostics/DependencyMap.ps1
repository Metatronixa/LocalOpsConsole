# Services/diagnostics/DependencyMap.ps1
param([string]$Name = "")

try {
    $services = if ($Name) {
        @(Get-Service -Name $Name -ErrorAction Stop)
    }
    else {
        # Focus on critical profile services + dependents overview
        $profileNames = @()
        $cfgDir = Join-Path (Get-LocRoot) "config\services"
        if (Test-Path $cfgDir) {
            Get-ChildItem $cfgDir -Filter "*.json" | ForEach-Object {
                try {
                    $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
                    if ($j.service) { $profileNames += [string]$j.service }
                }
                catch { Write-Debug $_.Exception.Message }
            }
        }
        if ($profileNames.Count -eq 0) { $profileNames = @("Spooler", "WinDefend", "wuauserv", "EventLog", "mpssvc", "Dnscache") }
        @(Get-Service -Name $profileNames -ErrorAction SilentlyContinue)
    }

    $map = @()
    foreach ($svc in $services) {
        $cim = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $svc.Name.Replace("'", "''")) -ErrorAction SilentlyContinue
        $deps = @()
        $dependents = @()
        try { $deps = @($svc.ServicesDependedOn | ForEach-Object { $_.Name }) } catch { Write-Debug $_.Exception.Message }
        try { $dependents = @($svc.DependentServices | ForEach-Object { $_.Name }) } catch { Write-Debug $_.Exception.Message }
        $map += [PSCustomObject]@{
            Name              = $svc.Name
            DisplayName       = $svc.DisplayName
            Status            = [string]$svc.Status
            StartType         = [string]$svc.StartType
            DependsOn         = $deps
            DependentServices = $dependents
            PathName          = if ($cim) { $cim.PathName } else { $null }
        }
    }

    New-ApiResult -Success $true -Message "Service dependency map" -Data @{
        Items = @($map)
        Count = $map.Count
    }
}
catch {
    New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
