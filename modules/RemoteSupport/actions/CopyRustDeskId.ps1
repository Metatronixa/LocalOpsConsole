try {
    $exe = Get-RustDeskExePath
    if (-not $exe) {
        return New-ApiResult -Success $false -Message "RustDesk is not installed - ID unavailable."
    }

    $id = Get-RustDeskClientId -ExePath $exe
    if ([string]::IsNullOrWhiteSpace($id)) {
        return New-ApiResult -Success $false -Message "Could not read RustDesk ID. Open RustDesk once or check that the client is configured."
    }

    return New-ApiResult -Success $true -Message "RustDesk ID ready for clipboard" -Data ([PSCustomObject]@{
        Id   = $id
        Note = "Passwords are never returned or displayed."
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
