param(
    [string]$Search = ""
)

try {
    $svcs = Get-Service -ErrorAction Stop | Sort-Object DisplayName
    if ($Search) {
        $svcs = $svcs | Where-Object {
            $_.Name -like "*$Search*" -or $_.DisplayName -like "*$Search*"
        }
    }

    $data = @($svcs | Select-Object -First 200 | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            DisplayName = $_.DisplayName
            Status      = [string]$_.Status
            StartType   = [string]$_.StartType
        }
    })

    return New-ApiResult -Success $true -Message ("{0} service(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
