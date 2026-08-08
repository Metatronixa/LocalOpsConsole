param(
    [Alias('Host')]
    [string]$TargetHost = "",
    [string]$PrinterName = ""
)

try {
    $hostParam = if (-not [string]::IsNullOrWhiteSpace($TargetHost)) {
        [string]$TargetHost
    }
    elseif ($PSBoundParameters.ContainsKey('Host')) {
        [string]$PSBoundParameters['Host']
    }
    else { "" }
    $target = Resolve-LocPrinterNetworkTarget -TargetHost $hostParam -PrinterName $PrinterName
    if (-not $target -or [string]::IsNullOrWhiteSpace($target.Host)) {
        return New-ApiResult -Success $false -Message "Host or TCP/IP PrinterName required" -Data ([PSCustomObject]@{
            Host = $hostParam; PrinterName = $PrinterName
        })
    }

    $probe = Invoke-LocPrinterNetworkProbe -HostName $target.Host -MaxTotalMs 8000
    $probe | Add-Member -NotePropertyName PrinterName -NotePropertyValue $target.PrinterName -Force
    $probe | Add-Member -NotePropertyName PortName -NotePropertyValue $target.PortName -Force

    $ok = ($probe.Ping -and $probe.Ping.Success) -or ($probe.Tcp9100 -and $probe.Tcp9100.Open) -or ($probe.Tcp515 -and $probe.Tcp515.Open)
    $msg = if ($ok) { "Network probe OK for $($target.Host)" } else { "Network probe completed with failures for $($target.Host)" }

    return New-ApiResult -Success $true -Message $msg -Data $probe
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
