param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Location,
    [bool]$Enabled = $false
)
try {
    if (-not (Test-Path $Location)) {
        return New-ApiResult -Success $false -Message "Registry location not found"
    }
    if ($Enabled) {
        return New-ApiResult -Success $false -Message "Re-enable from backup is not supported in v1; remove-only disable is available."
    }
    # Disable = remove Run value (caller should confirm in UI)
    Remove-ItemProperty -Path $Location -Name $Name -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Removed startup entry $Name" -Data ([PSCustomObject]@{ Name = $Name; Location = $Location; Enabled = $false })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
