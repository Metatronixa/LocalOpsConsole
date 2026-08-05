$r = Invoke-ToolCommand -FilePath "sfc.exe" -ArgumentList @("/verifyonly") -TimeoutSec 300
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "SFC /verifyonly" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
