# core/FleetEnrollToken.ps1 - Enrollment token and suggested agent URL

function Rotate-LocFleetEnrollToken {
    $token = New-LocEnrollmentToken
    $root = Get-LocRoot
    $settingsPath = Join-Path $root "settings.json"
    $settingsObj = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $settingsObj | Add-Member -NotePropertyName fleetEnrollToken -NotePropertyValue $token -Force
    ($settingsObj | ConvertTo-Json -Depth 5) | Set-Content $settingsPath -Encoding UTF8
    Initialize-LocSettings -RootPath $root

    Write-LocFleetJson -FileName "meta.json" -Data @{
        enrollToken = $token
        updatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    Add-LocFleetAudit -Action "EnrollTokenRotated"
    return New-ApiResult -Success $true -Message "Enrollment token rotated" -Data @{ Token = $token }
}

function Get-LocPreferredLanIPv4 {
    try {
        $nic = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE" -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -and (@($_.IPAddress) | Where-Object {
                    $_ -match '^\d+\.\d+\.\d+\.\d+$' -and
                    $_ -notmatch '^127\.' -and
                    $_ -notmatch '^169\.254\.'
                })
            } |
            Select-Object -First 1
        if (-not $nic) { return "" }
        $ipv4 = @($nic.IPAddress) | Where-Object {
            $_ -match '^\d+\.\d+\.\d+\.\d+$' -and
            $_ -notmatch '^127\.' -and
            $_ -notmatch '^169\.254\.'
        } | Select-Object -First 1
        if ($ipv4) { return [string]$ipv4 }
    }
    catch { Write-Debug $_.Exception.Message }
    return ""
}

function Get-LocFleetSuggestedServerUrl {
    param(
        [string]$PublicUrl = "",
        [string]$BindHost = "localhost",
        [int]$Port = 8787
    )

    $bind = if ($BindHost) { $BindHost.Trim() } else { "localhost" }
    $isLoopback = $bind -match '^(?i)(localhost|127\.0\.0\.1|::1)$'
    $isWildcard = $bind -match '^(?i)(0\.0\.0\.0|\+|\[::\])$'
    $lanIp = Get-LocPreferredLanIPv4
    $allowsRemote = -not $isLoopback

    if ($PublicUrl -and $PublicUrl.Trim()) {
        return [PSCustomObject]@{
            SuggestedUrl  = $PublicUrl.Trim().TrimEnd('/')
            DetectedLanIp = $lanIp
            BindHost      = $bind
            AllowsRemote  = $allowsRemote
            Source        = "fleetPublicUrl"
        }
    }

    if (-not $isLoopback -and -not $isWildcard) {
        return [PSCustomObject]@{
            SuggestedUrl  = "http://${bind}:$Port"
            DetectedLanIp = $lanIp
            BindHost      = $bind
            AllowsRemote  = $true
            Source        = "bindHost"
        }
    }

    if ($lanIp) {
        return [PSCustomObject]@{
            SuggestedUrl  = "http://${lanIp}:$Port"
            DetectedLanIp = $lanIp
            BindHost      = $bind
            AllowsRemote  = $allowsRemote
            Source        = "lanIp"
        }
    }

    return [PSCustomObject]@{
        SuggestedUrl  = "http://localhost:$Port"
        DetectedLanIp = ""
        BindHost      = $bind
        AllowsRemote  = $false
        Source        = "localhost"
    }
}

function Get-LocFleetEnrollToken {
    $settings = Get-LocSettings
    $token = if ($settings.fleetEnrollToken) { [string]$settings.fleetEnrollToken } else { "" }
    $publicUrl = if ($settings.fleetPublicUrl) { [string]$settings.fleetPublicUrl } else { "" }
    $port = if ($settings.port) { [int]$settings.port } else { 8787 }
    $bind = if ($settings.bindHost) { [string]$settings.bindHost } else { "localhost" }
    $hint = Get-LocFleetSuggestedServerUrl -PublicUrl $publicUrl -BindHost $bind -Port $port

    $bindMismatch = $false
    $bindWarning = ""
    $suggestedIsRemote = $hint.SuggestedUrl -and ($hint.SuggestedUrl -notmatch '(?i)localhost|127\.0\.0\.1')
    if ($suggestedIsRemote -and -not $hint.AllowsRemote) {
        $bindMismatch = $true
        $bindWarning = "Suggested agent URL is $($hint.SuggestedUrl) but bindHost is '$bind' (localhost only). Remote agents will fail to connect. Set bindHost to 0.0.0.0 and restart."
    }

    return New-ApiResult -Success $true -Message "Enrollment token" -Data @{
        Token         = $token
        SuggestedUrl  = $hint.SuggestedUrl
        PublicUrl     = $publicUrl
        DetectedLanIp = $hint.DetectedLanIp
        BindHost      = $hint.BindHost
        AllowsRemote  = [bool]$hint.AllowsRemote
        UrlSource     = $hint.Source
        BindMismatch  = $bindMismatch
        BindWarning   = $bindWarning
    }
}

