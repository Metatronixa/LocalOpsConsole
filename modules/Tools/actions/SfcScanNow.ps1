# SFC /scannow — may take a long time
$r = Invoke-ToolCommand -FilePath "sfc.exe" -ArgumentList @("/scannow") -TimeoutSec 3600
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "SFC /scannow finished (exit $($r.ExitCode))" -Data ([PSCustomObject]@{
    Output   = $r.Output
    ExitCode = $r.ExitCode
})
