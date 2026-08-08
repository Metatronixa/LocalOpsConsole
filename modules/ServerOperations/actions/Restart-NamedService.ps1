param([hashtable]$Params = @{})
try {
    $name = if ($Params.ServiceName) { [string]$Params.ServiceName } elseif ($Params.Name) { [string]$Params.Name } else { '' }
    if ([string]::IsNullOrWhiteSpace($name)) { return New-ApiResult -Success $false -Message 'ServiceName required' -StatusCode 400 }
    Restart-Service -Name $name -Force -ErrorAction Stop
    $svc = Get-Service -Name $name
    if (Get-Command Add-LocSystemTimelineEntry -ErrorAction SilentlyContinue) {
        Add-LocSystemTimelineEntry -Source 'ServerOperations' -Category 'Action' -Summary "Restarted service $name" -Data @{ ServiceName = $name; Status = [string]$svc.Status; RiskLevel = 'MODERATE' }
    }
    return New-ApiResult -Success $true -Message "Restarted $name ($($svc.Status))" -Data @{ ServiceName = $name; Status = [string]$svc.Status }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
