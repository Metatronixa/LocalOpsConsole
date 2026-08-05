param(
    [Parameter(Mandatory)]
    [string]$SettingId
)

try {
    $def = Get-LocConfigSettingDef -SettingId $SettingId
    $raw = Get-LocConfigSettingValue -Def $def
    $card = New-LocConfigSettingCard -Def $def -CurrentRaw $raw
    return New-ApiResult -Success $true -Message $card.Name -Data $card
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
