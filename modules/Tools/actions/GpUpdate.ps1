$r = Invoke-ToolCommand -FilePath "gpupdate.exe" -ArgumentList @("/force") -TimeoutSec 180
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "gpupdate /force" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
