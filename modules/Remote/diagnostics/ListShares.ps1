param(
    [Parameter(Mandatory)]
    [string]$ComputerName
)

try {
    $shares = @()
    try {
        $session = New-LocRemoteCimSession -ComputerName $ComputerName -OperationTimeoutSec 8
        Get-SmbShare -CimSession $session -ErrorAction Stop | ForEach-Object {
            $shares += [PSCustomObject]@{
                Name        = $_.Name
                Path        = $_.Path
                Description = $_.Description
                ShareType   = [string]$_.ShareType
                CurrentUsers= $_.CurrentUsers
            }
        }
        Remove-CimSession $session -ErrorAction SilentlyContinue
    }
    catch {
        $firstError = $_.Exception
        # Fallback: net view
        $out = net view "\\$ComputerName" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -and -not ($out -match 'Share name')) {
            if (Test-LocRemoteTimeoutError -Exception $firstError) {
                throw "ListShares timed out on $ComputerName. Verify firewall/RPC/WMI/SMB access and retry."
            }
            throw "Cannot list shares on $ComputerName. $($firstError.Message)"
        }
        foreach ($line in ($out -split "`r?`n")) {
            if ($line -match '^\s*(\S+)\s+(Disk|Print|Device|IPC)\s+(.*)$') {
                $shares += [PSCustomObject]@{
                    Name        = $Matches[1]
                    Path        = $null
                    Description = $Matches[3].Trim()
                    ShareType   = $Matches[2]
                    CurrentUsers= $null
                }
            }
        }
    }

    return New-ApiResult -Success $true -Message ("{0} share(s) on {1}" -f $shares.Count, $ComputerName) -Data @($shares)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message -Data ([PSCustomObject]@{ ComputerName = $ComputerName })
}
