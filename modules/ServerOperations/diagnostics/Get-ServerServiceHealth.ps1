param([hashtable]$Params = @{})
$null = $Params
try {
    $critical = @('LanmanServer','LanmanWorkstation','EventLog','RpcSs','Winmgmt')
    $rows = @()
    foreach ($n in $critical) {
        try {
            $svc = Get-Service -Name $n -ErrorAction Stop
            $rows += [PSCustomObject]@{ Name = $svc.Name; Status = [string]$svc.Status; StartType = [string]$svc.StartType }
        } catch {
            $rows += [PSCustomObject]@{ Name = $n; Status = 'Missing'; StartType = '' }
        }
    }
    return New-ApiResult -Success $true -Message 'Server service health' -Data @{ Available = $true; Services = @($rows) }
} catch { return New-ApiResult -Success $false -Message $_.Exception.Message }
