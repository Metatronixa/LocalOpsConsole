$r = Invoke-ToolCommand -FilePath "dism.exe" -ArgumentList @("/Online", "/Cleanup-Image", "/CheckHealth") -TimeoutSec 120
return New-ApiResult -Success ($r.ExitCode -eq 0) -Message "DISM CheckHealth" -Data ([PSCustomObject]@{ Output = $r.Output; ExitCode = $r.ExitCode })
