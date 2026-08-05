try {
    $problems = @()
    Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -ne "OK" } | ForEach-Object {
        $problems += [PSCustomObject]@{
            FriendlyName = $_.FriendlyName
            InstanceId   = $_.InstanceId
            Class        = $_.Class
            Status       = [string]$_.Status
            Problem      = [string]$_.Problem
        }
    }
    return New-ApiResult -Success $true -Message ("{0} problem device(s)" -f $problems.Count) -Data @($problems)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
