try {
    $exe = Get-RustDeskExePath
    if (-not $exe) {
        return New-ApiResult -Success $false -Message "RustDesk is not installed."
    }

    Start-Process -FilePath $exe -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Opening RustDesk" -Data ([PSCustomObject]@{
        ExePath = $exe
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
