$r = Invoke-ToolCommand -FilePath "systeminfo.exe" -TimeoutSec 90
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "systeminfo" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
