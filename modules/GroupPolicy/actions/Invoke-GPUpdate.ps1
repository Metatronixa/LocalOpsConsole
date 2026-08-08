param([hashtable]$Params = @{})
try {
    $target = if ($Params.Target) { [string]$Params.Target } else { 'Computer' }
    $cmdArgs = @('/force')
    if ($target -match '(?i)user') { $cmdArgs = @('/force', '/Target:User') }
    elseif ($target -match '(?i)computer') { $cmdArgs = @('/force', '/Target:Computer') }
    $p = Start-Process -FilePath 'gpupdate.exe' -ArgumentList $cmdArgs -Wait -PassThru -NoNewWindow
    return New-ApiResult -Success ($p.ExitCode -eq 0) -Message "gpupdate exit $($p.ExitCode)" -Data @{ ExitCode = $p.ExitCode; Action = 'Invoke-GPUpdate' }
} catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
