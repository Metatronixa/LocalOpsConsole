param(
    [string]$ComputerName = ""
)

$gate = Assert-LocRemoteComputerName -ComputerName $ComputerName
if ($gate) { return $gate }

$ComputerName = $ComputerName.Trim().TrimStart('\\')

try {
    $shares = @()
    $method = "Cim/SmbShare"
    $reachable = Test-RemoteHostOnline -ComputerName $ComputerName -TimeoutMs 2000
    if (-not $reachable) {
        return New-ApiResult -Success $false -Message "Host $ComputerName did not respond on ICMP/TCP 445 within 2s. Pick another PC or check firewall/SMB." -Data ([PSCustomObject]@{
            ComputerName = $ComputerName
            Reachable    = $false
        }) -StatusCode 504
    }

    $session = $null
    try {
        $session = New-LocRemoteCimSession -ComputerName $ComputerName -OperationTimeoutSec 5
        Get-SmbShare -CimSession $session -ErrorAction Stop | ForEach-Object {
            $shares += [PSCustomObject]@{
                Name         = $_.Name
                Path         = $_.Path
                Description  = $_.Description
                ShareType    = [string]$_.ShareType
                CurrentUsers = $_.CurrentUsers
            }
        }
    }
    catch {
        $cimErr = $_.Exception
        try {
            $shares = @(Invoke-LocNetViewShares -ComputerName $ComputerName -TimeoutMs 6000)
            $method = "net view"
        }
        catch {
            $msg = if (Test-LocRemoteTimeoutError -Exception $cimErr) {
                "ListShares timed out on ${ComputerName}. Prefer the LAN IP (\\\\x.x.x.x). Also verify firewall/RPC/WMI/SMB and that you selected the right PC."
            } else {
                "Cannot list shares on ${ComputerName}. $($cimErr.Message) / $($_.Exception.Message)"
            }
            return New-ApiResult -Success $false -Message $msg -Data ([PSCustomObject]@{
                ComputerName = $ComputerName
                Reachable    = $true
            }) -StatusCode 504
        }
    }
    finally {
        if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }
    }

    return New-ApiResult -Success $true -Message ("{0} share(s) on {1} via {2}" -f $shares.Count, $ComputerName, $method) -Data @($shares)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -Data ([PSCustomObject]@{ ComputerName = $ComputerName })
}
