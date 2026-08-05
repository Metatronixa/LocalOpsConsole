param([string]$Drive = "C:")
# Read-only status probe (no /F)
$r = Invoke-ToolCommand -FilePath "chkdsk.exe" -ArgumentList @($Drive) -TimeoutSec 120
return New-ApiResult -Success ($r.ExitCode -in @(0, 1, 2, 3)) -Message "chkdsk $Drive (read-only)" -Data ([PSCustomObject]@{ Drive = $Drive; Output = $r.Output; ExitCode = $r.ExitCode })
