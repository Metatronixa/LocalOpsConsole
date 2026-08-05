try {
    $status = Get-RustDeskStatusSnapshot
    $msg = if ($status.Installed) {
        "RustDesk installed" + $(if ($status.Version) { " v$($status.Version)" } else { '' })
    }
    else {
        "RustDesk not detected"
    }
    return New-ApiResult -Success $true -Message $msg -Data $status
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
