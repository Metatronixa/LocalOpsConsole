# core/Response.ps1 - Standardized API result + JSON writer

function New-ApiResult {
    param(
        [bool]$Success = $true,
        [string]$Message = "",
        [object]$Data = $null,
        [int]$StatusCode = 200
    )

    if ($null -eq $Data) { $Data = @{} }

    return [PSCustomObject]@{
        Success    = $Success
        Message    = $Message
        Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Data       = $Data
        StatusCode = $StatusCode
    }
}

function Test-LocIsListData {
    param([object]$Data)
    if ($null -eq $Data) { return $false }
    if ($Data -is [string]) { return $false }
    if ($Data -is [hashtable] -or $Data -is [System.Collections.IDictionary]) { return $false }
    if ($Data -is [PSCustomObject]) { return $false }
    return ($Data -is [System.Collections.IEnumerable])
}

function ConvertTo-LocJsonArray {
    param([object[]]$Items)
    if ($null -eq $Items -or $Items.Count -eq 0) { return "[]" }
    if ($Items.Count -eq 1) {
        return "[" + ($Items[0] | ConvertTo-Json -Depth 7 -Compress) + "]"
    }
    $tmp = $Items | ConvertTo-Json -Depth 7 -Compress
    if ($tmp.TrimStart().StartsWith("[")) { return $tmp }
    return "[$tmp]"
}

function Send-JsonResponse {
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,
        [bool]$Success,
        [string]$Message,
        [object]$Data = @{},
        [int]$StatusCode = 200
    )

    $response = $Context.Response
    $response.StatusCode = $StatusCode
    $response.ContentType = "application/json; charset=utf-8"
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Cache-Control", "no-store")

    if ($null -eq $Data) { $Data = @{} }

    if (Test-LocIsListData -Data $Data) {
        $itemsJson = ConvertTo-LocJsonArray -Items @($Data)
        $envelope = [PSCustomObject]@{
            Success   = $Success
            Message   = $Message
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Data      = $null
        } | ConvertTo-Json -Depth 4 -Compress
        $payload = $envelope -replace '"Data":null', ('"Data":' + $itemsJson)
    }
    else {
        $payload = [PSCustomObject]@{
            Success   = $Success
            Message   = $Message
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Data      = $Data
        } | ConvertTo-Json -Depth 8 -Compress
    }

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}

function ConvertTo-Hashtable {
    param([object]$InputObject)

    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }

    $hash = @{}
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = $prop.Value
        }
        return $hash
    }

    return @{ Value = $InputObject }
}
