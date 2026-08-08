# Shared runner for Tools module
function Invoke-ToolCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSec = 20
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($ArgumentList -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    # Start reads before waiting — avoids stdout pipe deadlock without PS event callbacks
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { Write-Debug $_.Exception.Message }
        try { [void]$p.WaitForExit(3000) } catch { Write-Debug $_.Exception.Message }
        $partialOut = ""
        $partialErr = ""
        try { if ($outTask.IsCompleted) { $partialOut = $outTask.Result } } catch { Write-Debug $_.Exception.Message }
        try { if ($errTask.IsCompleted) { $partialErr = $errTask.Result } } catch { Write-Debug $_.Exception.Message }
        return [PSCustomObject]@{
            ExitCode = -1
            Output   = ("Timed out after ${TimeoutSec}s`n" + $partialOut + "`n" + $partialErr).Trim()
            Error    = $partialErr
            TimedOut = $true
        }
    }

    $stdout = ""
    $stderr = ""
    try { $stdout = $outTask.GetAwaiter().GetResult() } catch { $stdout = "" }
    try { $stderr = $errTask.GetAwaiter().GetResult() } catch { $stderr = "" }

    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        Output   = ($stdout + "`n" + $stderr).Trim()
        Error    = ([string]$stderr).Trim()
        TimedOut = $false
    }
}
