# TestBrowserTargets.ps1
try {
    $targets = @(
        "https://www.microsoft.com",
        "https://www.google.com",
        "https://github.com",
        "https://www.cloudflare.com"
    )
    $results = @()
    foreach ($url in $targets) {
        $r = Invoke-LocHttpsHead -Url $url -TimeoutSec 3
        $results += [PSCustomObject]@{
            Url        = $url
            Success    = $r.Success
            StatusCode = $r.StatusCode
            ElapsedMs  = $r.ElapsedMs
            Message    = if ($r.Message) { $r.Message } else { $null }
        }
    }
    $pass = @($results | Where-Object { $_.Success }).Count
    return New-ApiResult -Success $true -Message ("{0}/{1} targets reachable" -f $pass, $results.Count) -Data @($results)
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
