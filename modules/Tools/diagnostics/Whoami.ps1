$r = Invoke-ToolCommand -FilePath "whoami.exe" -ArgumentList @("/all")
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "whoami /all" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
