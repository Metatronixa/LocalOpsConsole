param(
    [Parameter(Mandatory)][int]$LineNumber
)
try {
    if ($LineNumber -lt 1) {
        return New-ApiResult -Success $false -Message "LineNumber required" -StatusCode 400
    }
    $path = Get-LocHostsFilePath
    $lines = [System.IO.File]::ReadAllLines($path)
    if ($LineNumber -gt $lines.Length) {
        return New-ApiResult -Success $false -Message "Line out of range" -StatusCode 400
    }
    $idx = $LineNumber - 1
    $raw = $lines[$idx]
    $trimmed = $raw.TrimStart()
    if ($trimmed.StartsWith('#')) {
        # uncomment — strip first #
        $hash = $raw.IndexOf('#')
        $lines[$idx] = $raw.Remove($hash, 1).TrimStart()
        $state = "enabled"
    }
    else {
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return New-ApiResult -Success $false -Message "Cannot toggle blank line" -StatusCode 400
        }
        $lines[$idx] = "# $raw"
        $state = "disabled"
    }
    $bak = Backup-LocHostsFile
    [System.IO.File]::WriteAllLines($path, $lines)
    return New-ApiResult -Success $true -Message "Hosts entry $state" -Data ([PSCustomObject]@{
        LineNumber = $LineNumber; State = $state; Raw = $lines[$idx]; Backup = $bak
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
