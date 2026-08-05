param(
    [string]$IP = "",
    [string]$Hostname = "",
    [int]$LineNumber = 0
)
try {
    $path = Get-LocHostsFilePath
    $lines = [System.Collections.Generic.List[string]]::new()
    [System.IO.File]::ReadAllLines($path) | ForEach-Object { [void]$lines.Add($_) }
    $removed = @()
    $newLines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $i + 1
        $raw = $lines[$i]
        $drop = $false
        if ($LineNumber -gt 0 -and $ln -eq $LineNumber) {
            $drop = $true
        }
        elseif ($IP -or $Hostname) {
            $parsed = @(Parse-LocHostsFile -Content $raw)
            foreach ($e in $parsed) {
                $ipMatch = (-not $IP) -or ($e.IP -eq $IP)
                $hostMatch = (-not $Hostname) -or ($e.Names -contains $Hostname -or $e.Hostnames -match [regex]::Escape($Hostname))
                if ($ipMatch -and $hostMatch) { $drop = $true }
            }
        }
        if ($drop) {
            $removed += [PSCustomObject]@{ LineNumber = $ln; Raw = $raw }
        }
        else {
            [void]$newLines.Add($raw)
        }
    }
    if ($removed.Count -eq 0) {
        return New-ApiResult -Success $false -Message "No matching hosts entry found" -StatusCode 404
    }
    $bak = Backup-LocHostsFile
    [System.IO.File]::WriteAllLines($path, $newLines.ToArray())
    return New-ApiResult -Success $true -Message ("Removed {0} line(s)" -f $removed.Count) -Data ([PSCustomObject]@{
        Removed = @($removed); Backup = $bak
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
}
