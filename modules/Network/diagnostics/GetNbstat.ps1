try {
    function Invoke-LocNbtstat {
        param([string]$Args)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "nbtstat.exe"
        $psi.Arguments = $Args
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit(8000)) {
            try { $p.Kill() } catch { }
            return [PSCustomObject]@{ TimedOut = $true; StdOut = ""; StdErr = "Timed out after 8s" }
        }
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        return [PSCustomObject]@{ TimedOut = $false; StdOut = $out; StdErr = $err; ExitCode = $p.ExitCode }
    }

    $local = Invoke-LocNbtstat -Args "-n"
    $cache = Invoke-LocNbtstat -Args "-r"

    return New-ApiResult -Success $true -Message "nbtstat -n / -r" -Data ([PSCustomObject]@{
        LocalNameTable = [PSCustomObject]@{
            TimedOut = [bool]$local.TimedOut
            Output   = [string]$local.StdOut
            Error    = [string]$local.StdErr
        }
        ResolutionCache = [PSCustomObject]@{
            TimedOut = [bool]$cache.TimedOut
            Output   = [string]$cache.StdOut
            Error    = [string]$cache.StdErr
        }
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
