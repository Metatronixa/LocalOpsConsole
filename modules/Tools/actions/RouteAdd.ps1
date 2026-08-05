param(
    [Parameter(Mandatory)]
    [string]$Destination,
    [Parameter(Mandatory)]
    [string]$Gateway,
    [string]$Mask = "255.255.255.255",
    [string]$Permanent = "false"
)

try {
    if ([string]::IsNullOrWhiteSpace($Destination) -or [string]::IsNullOrWhiteSpace($Gateway)) {
        return New-ApiResult -Success $false -Message "Destination and Gateway are required"
    }
    if ([string]::IsNullOrWhiteSpace($Mask)) { $Mask = "255.255.255.255" }

    $isPermanent = $false
    if ($Permanent -is [bool]) {
        $isPermanent = [bool]$Permanent
    }
    else {
        $isPermanent = ([string]$Permanent).ToLower() -in @("1", "true", "yes", "y")
    }

    $args = @()
    if ($isPermanent) { $args += "-p" }
    $args += @("add", $Destination, $Mask, $Gateway)

    $r = Invoke-ToolCommand -FilePath "route.exe" -ArgumentList $args -TimeoutSec 20
    $ok = ($r.ExitCode -eq 0)
    return New-ApiResult -Success $ok -Message $(if ($ok) { "Route added" } else { "Route add failed (exit $($r.ExitCode))" }) -Data ([PSCustomObject]@{
        Destination = $Destination
        Mask        = $Mask
        Gateway     = $Gateway
        Permanent   = $isPermanent
        Output      = $r.Output
        ExitCode    = $r.ExitCode
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
