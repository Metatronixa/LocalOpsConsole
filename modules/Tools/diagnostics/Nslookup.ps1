param([string]$HostName = "www.microsoft.com")
$r = Invoke-ToolCommand -FilePath "nslookup.exe" -ArgumentList @($HostName)
return New-ApiResult -Success ($r.ExitCode -eq 0 -or [bool]$r.Output) -Message "nslookup $HostName" -Data ([PSCustomObject]@{ HostName = $HostName; Output = $r.Output; ExitCode = $r.ExitCode })
