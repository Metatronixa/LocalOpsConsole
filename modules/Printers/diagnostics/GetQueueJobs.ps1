param([string]$PrinterName = "")

try {
    $jobs = if ($PrinterName) {
        @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue)
    }
    else {
        $all = @()
        Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
            $all += @(Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue)
        }
        $all
    }

    $data = @($jobs | ForEach-Object {
        $pages = 0
        try {
            if ($_.PSObject.Properties.Name -contains "TotalPages") { $pages = [int]$_.TotalPages }
            elseif ($_.PSObject.Properties.Name -contains "PagesPrinted") { $pages = [int]$_.PagesPrinted }
        }
        catch { Write-Debug $_.Exception.Message }

        $owner = ""
        try {
            if ($_.PSObject.Properties.Name -contains "UserName") { $owner = [string]$_.UserName }
            elseif ($_.PSObject.Properties.Name -contains "SubmittedBy") { $owner = [string]$_.SubmittedBy }
        }
        catch { Write-Debug $_.Exception.Message }

        [PSCustomObject]@{
            PrinterName = [string]$_.PrinterName
            JobId       = [int]$_.Id
            Document    = [string]$_.DocumentName
            Owner       = $owner
            Size        = if ($null -ne $_.Size) { [long]$_.Size } else { 0 }
            Pages       = $pages
            Age         = Format-LocJobAge -SubmittedTime $_.SubmittedTime
            Status      = [string]$_.JobStatus
            Submitted   = if ($_.SubmittedTime) { $_.SubmittedTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        }
    })

    return New-ApiResult -Success $true -Message ("{0} job(s)" -f $data.Count) -Data $data
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
