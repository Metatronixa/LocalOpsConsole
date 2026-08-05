# Remote helpers
function Test-RemoteHostOnline {
    param([string]$ComputerName)
    try {
        return [bool](Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }
    catch { return $false }
}

function New-LocRemoteCimSession {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [int]$OperationTimeoutSec = 8
    )

    try {
        $opt = New-CimSessionOption -Protocol Dcom -OperationTimeoutSec $OperationTimeoutSec -ErrorAction Stop
        return New-CimSession -ComputerName $ComputerName -SessionOption $opt -ErrorAction Stop
    }
    catch {
        # Best effort fallback for older hosts/environments that may reject session options.
        return New-CimSession -ComputerName $ComputerName -ErrorAction Stop
    }
}

function Test-LocRemoteTimeoutError {
    param([System.Exception]$Exception)
    if ($null -eq $Exception) { return $false }
    $msg = [string]$Exception.Message
    return (
        $msg -match '(?i)timed?\s*out' -or
        $msg -match '(?i)The WS-Management service cannot process the request' -or
        $msg -match '(?i)WinRM cannot complete the operation'
    )
}
