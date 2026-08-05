param(
    [Parameter(Mandatory)]
    [string]$SettingId,
    [string]$Value = ""
)

try {
    $def = Get-LocConfigSettingDef -SettingId $SettingId
    if (Test-LocConfigReadOnly -Def $def) {
        return New-ApiResult -Success $false -Message ("{0} is read-only" -f $def.name)
    }
    if ([bool]$def.requiresAdmin) {
        $denied = Require-Admin -ActionName ("Configuration/{0}" -f $def.id)
        if ($denied) { return $denied }
    }

    $before = Get-LocConfigSettingValue -Def $def
    $target = $def.recommended
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $target = $Value
    }

    $after = Set-LocConfigSettingValue -Def $def -Value $target
    $card = New-LocConfigSettingCard -Def $def -CurrentRaw $after

    $notes = @()
    if ($def.requiresExplorerRestart) { $notes += "Restart Explorer or sign out for UI to refresh." }
    if ($def.requiresLogoff) { $notes += "Logoff may be required." }
    if ($def.requiresRestart) { $notes += "Restart may be required." }

    return New-ApiResult -Success $true -Message ("Applied {0}" -f $def.name) -Data ([PSCustomObject]@{
        Setting                 = $card
        Before                  = $before
        After                   = $after
        RequiresExplorerRestart = [bool]$def.requiresExplorerRestart
        RequiresRestart         = [bool]$def.requiresRestart
        RequiresLogoff          = [bool]$def.requiresLogoff
        Note                    = ($notes -join " ")
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
