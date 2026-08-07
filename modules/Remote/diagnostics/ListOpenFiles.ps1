param([string]$ComputerName = "")

$gate = Assert-LocRemoteComputerName -ComputerName $ComputerName
if ($gate) { return $gate }
$ComputerName = $ComputerName.Trim().TrimStart('\\')

try {
    if (-not (Test-RemoteHostOnline -ComputerName $ComputerName -TimeoutMs 2000)) {
        return New-ApiResult -Success $false -Message "Host $ComputerName unreachable (ICMP/TCP 445). Select another PC." -StatusCode 504
    }
    $session = New-LocRemoteCimSession -ComputerName $ComputerName -OperationTimeoutSec 5
    $files = @(Get-SmbOpenFile -CimSession $session -ErrorAction Stop | Select-Object -First 200 | ForEach-Object {
        [PSCustomObject]@{
            FileId       = $_.FileId
            Path         = $_.Path
            ShareRelative= $_.ShareRelativePath
            ClientName   = $_.ClientComputerName
            UserName     = $_.ClientUserName
            SessionId    = $_.SessionId
        }
    })
    Remove-CimSession $session -ErrorAction SilentlyContinue
    return New-ApiResult -Success $true -Message ("{0} open file(s) on {1}" -f $files.Count, $ComputerName) -Data @($files)
}
catch {
    if (Test-LocRemoteTimeoutError -Exception $_.Exception) {
        return New-ApiResult -Success $false -Message "Open files timed out on ${ComputerName}. Prefer LAN IP; needs admin + firewall allowing WMI/RPC/SMB (Explorer share browse alone is not enough)." -StatusCode 504
    }
    return New-ApiResult -Success $false -Message "Open files failed on ${ComputerName}: $($_.Exception.Message). Requires admin rights and File Server role/SMB."
}
