$r = Invoke-ToolCommand -FilePath "route.exe" -ArgumentList @("print")
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "route print" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
