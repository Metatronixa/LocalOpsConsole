param([hashtable]$Params = @{})
try {
    $st = Import-LocADModule
    if (-not $st.Available) {
        return New-ApiResult -Success $true -Message 'AD not available' -Data @{ Available = $false; Status = $st }
    }
    $id = Assert-LocADUserName -Identity $(if ($Params.Identity) { $Params.Identity } elseif ($Params.User) { $Params.User } else { '' })
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 50 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match [regex]::Escape($id) } |
            Select-Object -First 10 TimeCreated, Id, Message)
    } catch { Write-Debug $_.Exception.Message }
    $sources = @($events | ForEach-Object {
        $m = $_.Message
        $caller = if ($m -match 'Caller Computer Name:\s*(\S+)') { $Matches[1] } else { '' }
        [PSCustomObject]@{ Time = $_.TimeCreated.ToString('o'); CallerComputer = $caller }
    })
    return New-ApiResult -Success $true -Message 'Lockout source probe' -Data @{
        Available = $true
        Identity = $id
        Sources = @($sources)
        EventCount = @($events).Count
    }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
