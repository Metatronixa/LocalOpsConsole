# Remote helpers
function Test-RemoteHostOnline {
    param(
        [string]$ComputerName,
        [int]$TimeoutMs = 1500
    )
    if ([string]::IsNullOrWhiteSpace($ComputerName)) { return $false }
    # TCP 445 only — ICMP can hang several seconds on filtered networks
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($ComputerName, 445, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok) {
            try {
                $tcp.EndConnect($iar)
                if ($tcp.Connected) {
                    $tcp.Close()
                    return $true
                }
            }
            catch { }
        }
        else {
            try { $tcp.Close() } catch { }
        }
    }
    catch { }
    return $false
}

function New-LocRemoteCimSession {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [int]$OperationTimeoutSec = 5
    )

    $opt = New-CimSessionOption -Protocol Dcom -OperationTimeoutSec $OperationTimeoutSec -ErrorAction Stop
    return New-CimSession -ComputerName $ComputerName -SessionOption $opt -ErrorAction Stop
}

function Test-LocRemoteTimeoutError {
    param([System.Exception]$Exception)
    if ($null -eq $Exception) { return $false }
    $msg = [string]$Exception.Message
    return (
        $msg -match '(?i)timed?\s*out' -or
        $msg -match '(?i)The WS-Management service cannot process the request' -or
        $msg -match '(?i)WinRM cannot complete the operation' -or
        $msg -match '(?i)RPC server is unavailable'
    )
}

function Assert-LocRemoteComputerName {
    param([string]$ComputerName)
    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        return New-ApiResult -Success $false -Message "Select a computer first: Discover Computers, then click a PC (or type a name/IP)." -StatusCode 400
    }
    return $null
}

function Invoke-LocNetViewShares {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [int]$TimeoutMs = 6000
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\net.exe"
    $psi.Arguments = "view \\$ComputerName"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch { }
        throw "net view timed out after $([math]::Round($TimeoutMs/1000))s on $ComputerName"
    }
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $combined = ($out + "`n" + $err).Trim()
    if ($p.ExitCode -ne 0 -and $combined -notmatch 'Share name') {
        throw "net view failed on ${ComputerName}: $combined"
    }
    $shares = @()
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '^\s*(\S+)\s+(Disk|Print|Device|IPC)\s+(.*)$') {
            $shares += [PSCustomObject]@{
                Name         = $Matches[1]
                Path         = $null
                Description  = $Matches[3].Trim()
                ShareType    = $Matches[2]
                CurrentUsers = $null
            }
        }
    }
    return @($shares)
}
