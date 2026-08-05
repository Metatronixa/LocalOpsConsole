try {
    Restart-Service -Name Spooler -Force -ErrorAction Stop
    $s = Get-Service Spooler
    return New-ApiResult -Success $true -Message "Print Spooler restarted" -Data ([PSCustomObject]@{ Status = [string]$s.Status })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
