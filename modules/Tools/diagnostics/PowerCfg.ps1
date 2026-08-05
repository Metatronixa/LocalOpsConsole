$r = Invoke-ToolCommand -FilePath "powercfg.exe" -ArgumentList @("/query")
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "powercfg /query" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
