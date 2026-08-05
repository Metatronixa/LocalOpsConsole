$r = Invoke-ToolCommand -FilePath "ipconfig.exe" -ArgumentList @("/all")
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "ipconfig /all" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
