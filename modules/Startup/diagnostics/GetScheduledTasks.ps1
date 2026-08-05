param([string]$Search = "")
try {
    $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne "Disabled" -or $true }
    if ($Search) {
        $tasks = $tasks | Where-Object { $_.TaskName -like "*$Search*" -or $_.TaskPath -like "*$Search*" }
    }
    $data = @($tasks | Select-Object -First 100 | ForEach-Object {
        [PSCustomObject]@{
            TaskName = $_.TaskName
            TaskPath = $_.TaskPath
            State    = [string]$_.State
            Author   = $_.Author
        }
    })
    return New-ApiResult -Success $true -Message ("{0} task(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
