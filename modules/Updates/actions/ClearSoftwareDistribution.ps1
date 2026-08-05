try {
    $sd = "$env:SystemRoot\SoftwareDistribution"
    $catroot2 = "$env:SystemRoot\System32\catroot2"
    Stop-Service wuauserv, bits, cryptsvc -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    $renamed = @()
    foreach ($path in @($sd, $catroot2)) {
        if (Test-Path $path) {
            $backup = "$path.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Rename-Item -Path $path -NewName (Split-Path $backup -Leaf) -ErrorAction SilentlyContinue
            if (-not (Test-Path $path)) { $renamed += $backup }
        }
    }

    Start-Service wuauserv, bits, cryptsvc -ErrorAction SilentlyContinue
    return New-ApiResult -Success $true -Message "SoftwareDistribution/catroot2 reset" -Data ([PSCustomObject]@{
        Renamed = @($renamed)
        Warning = "Windows Update will rebuild caches on next check."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
