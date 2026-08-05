$r = Invoke-ToolCommand -FilePath "gpresult.exe" -ArgumentList @("/R") -TimeoutSec 90
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "gpresult /R" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
