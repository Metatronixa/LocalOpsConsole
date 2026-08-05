param(
    [Parameter(Mandatory)][string]$IP,
    [Parameter(Mandatory)][string]$Hostname,
    [string]$Comment = ""
)
try {
    $IP = $IP.Trim()
    $Hostname = $Hostname.Trim()
    if ([string]::IsNullOrWhiteSpace($IP) -or [string]::IsNullOrWhiteSpace($Hostname)) {
        return New-ApiResult -Success $false -Message "IP and Hostname are required" -StatusCode 400
    }
    if ($Hostname -match '\s') {
        return New-ApiResult -Success $false -Message "Hostname must be a single token" -StatusCode 400
    }
    $path = Get-LocHostsFilePath
    $bak = Backup-LocHostsFile
    $line = "{0}`t{1}" -f $IP, $Hostname
    if ($Comment) { $line = "$line`t# $Comment" }
    Add-Content -LiteralPath $path -Value $line -Encoding ASCII
    return New-ApiResult -Success $true -Message "Added hosts entry" -Data ([PSCustomObject]@{
        IP = $IP; Hostname = $Hostname; Backup = $bak; Line = $line
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
