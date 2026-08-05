$r = Invoke-ToolCommand -FilePath "netstat.exe" -ArgumentList @("-ano") -TimeoutSec 15
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "netstat -ano" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
