# DISM RestoreHealth — may take a long time
$r = Invoke-ToolCommand -FilePath "dism.exe" -ArgumentList @("/Online", "/Cleanup-Image", "/RestoreHealth") -TimeoutSec 3600
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "DISM RestoreHealth finished (exit $($r.ExitCode))" -Data ([PSCustomObject]@{
    Output   = $r.Output
    ExitCode = $r.ExitCode
})
