param(
    [Parameter(Mandatory)]
    [string]$ComputerName
)

try {
    $session = New-LocRemoteCimSession -ComputerName $ComputerName -OperationTimeoutSec 8
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
        return New-ApiResult -Success $false -Message "Open files timed out on ${ComputerName}. Check admin rights plus firewall/RPC/WMI/SMB access on the target."
    }
    return New-ApiResult -Success $false -Message "Open files failed on ${ComputerName}: $($_.Exception.Message). Requires admin rights and File Server role/SMB."
}
