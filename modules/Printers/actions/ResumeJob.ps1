param(
    [Parameter(Mandatory)]
    [string]$PrinterName,
    [Parameter(Mandatory)]
    [int]$JobId
)

try {
    Resume-PrintJob -PrinterName $PrinterName -ID $JobId -ErrorAction Stop
    return New-ApiResult -Success $true -Message "Resumed job $JobId on $PrinterName" -Data ([PSCustomObject]@{
        PrinterName = $PrinterName
        JobId       = $JobId
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
