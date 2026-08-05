try {
    $path = Get-LocHostsFilePath
    if (-not (Test-Path -LiteralPath $path)) {
        return New-ApiResult -Success $false -Message "Hosts file not found" -Data @{ Path = $path }
    }
    $raw = [System.IO.File]::ReadAllText($path)
    $rows = @(Parse-LocHostsFile -Content $raw)
    return New-ApiResult -Success $true -Message ("{0} hosts entr{1}" -f $rows.Count, $(if ($rows.Count -eq 1) { 'y' } else { 'ies' })) -Data ([PSCustomObject]@{
        Path     = $path
        Backup   = Get-LocHostsBackupPath
        Entries  = @($rows)
        LineCount = @($raw -split "`r?`n").Count
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
