$r = Invoke-ToolCommand -FilePath "arp.exe" -ArgumentList @("-a")
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "arp -a" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
