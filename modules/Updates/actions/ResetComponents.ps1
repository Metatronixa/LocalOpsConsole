try {
    $services = @("wuauserv", "bits", "cryptsvc", "msiserver")
    foreach ($s in $services) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
    foreach ($s in $services) {
        Start-Service -Name $s -ErrorAction SilentlyContinue
    }
    $status = Get-Service $services -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Status = [string]$_.Status }
    }
    return New-ApiResult -Success $true -Message "Windows Update services recycled" -Data ([PSCustomObject]@{ Services = @($status) })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
