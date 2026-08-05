# GetRoutes.ps1
try {
    $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1

    $staticRoutes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.RouteMetric -lt 256 -and $_.DestinationPrefix -ne "0.0.0.0/0" } |
        Sort-Object RouteMetric |
        Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                DestinationPrefix = $_.DestinationPrefix
                NextHop           = $_.NextHop
                InterfaceAlias    = $_.InterfaceAlias
                RouteMetric       = $_.RouteMetric
                Publish           = $_.Publish
            }
        })

    return New-ApiResult -Success $true -Message "Routing table (summary)" -Data ([PSCustomObject]@{
        DefaultRoute = if ($defaultRoute) {
            [PSCustomObject]@{
                DestinationPrefix = $defaultRoute.DestinationPrefix
                NextHop           = $defaultRoute.NextHop
                InterfaceAlias    = $defaultRoute.InterfaceAlias
                RouteMetric       = $defaultRoute.RouteMetric
            }
        } else { $null }
        StaticRoutes = @($staticRoutes)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
