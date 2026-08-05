param(
    [Parameter(Mandatory)]
    [string]$ComputerName
)

try {
    $session = New-LocRemoteCimSession -ComputerName $ComputerName -OperationTimeoutSec 8
    $sessions = @(Get-SmbSession -CimSession $session -ErrorAction Stop | Select-Object -First 200 | ForEach-Object {
        [PSCustomObject]@{
            SessionId    = $_.SessionId
            ClientName   = $_.ClientComputerName
            UserName     = $_.ClientUserName
            NumOpens     = $_.NumOpens
            Dialect      = $_.Dialect
            SecondsOpen  = $_.SecondsExists
        }
    })
    Remove-CimSession $session -ErrorAction SilentlyContinue
    return New-ApiResult -Success $true -Message ("{0} SMB session(s) on {1}" -f $sessions.Count, $ComputerName) -Data @($sessions)
}
catch {
    if (Test-LocRemoteTimeoutError -Exception $_.Exception) {
        return New-ApiResult -Success $false -Message "Sessions query timed out on ${ComputerName}. Check admin rights plus firewall/RPC/WMI/SMB access on the target."
    }
    return New-ApiResult -Success $false -Message "Sessions failed on ${ComputerName}: $($_.Exception.Message)"
}
