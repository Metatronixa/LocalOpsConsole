# core/FleetAuth.ps1 - Fleet agent authentication (HMAC-SHA256)

function New-LocEnrollmentToken {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function New-LocAgentSecret {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function Get-LocHmacHex {
    param(
        [Parameter(Mandatory)]
        [string]$Secret,
        [Parameter(Mandatory)]
        [string]$Message
    )

    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
    $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $keyBytes
    try {
        $hash = $hmac.ComputeHash($msgBytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $hmac.Dispose()
    }
}

function Get-LocFleetAgentSecret {
    param([Parameter(Mandatory)] [string]$AgentId)

    $data = Get-LocFleetAgentsData
    $agents = $data.agents
    if ($agents -is [PSCustomObject]) {
        $prop = $agents.PSObject.Properties | Where-Object { $_.Name -eq $AgentId } | Select-Object -First 1
        if (-not $prop) { return $null }
        $agent = $prop.Value
        if ($agent.Revoked) { return $null }
        return [string]$agent.Secret
    }
    if ($agents -is [hashtable] -and $agents.ContainsKey($AgentId)) {
        $agent = $agents[$AgentId]
        if ($agent.Revoked) { return $null }
        return [string]$agent.Secret
    }
    return $null
}

function Test-LocAgentSignature {
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerRequest]$Request,
        [Parameter(Mandatory)]
        [string]$Body,
        [int]$MaxSkewSeconds = 300
    )

    $agentId = $Request.Headers["X-Loc-Agent"]
    $timestamp = $Request.Headers["X-Loc-Timestamp"]
    $signature = $Request.Headers["X-Loc-Signature"]

    if ([string]::IsNullOrWhiteSpace($agentId)) {
        return New-ApiResult -Success $false -Message "Missing X-Loc-Agent header" -StatusCode 401
    }
    if ([string]::IsNullOrWhiteSpace($timestamp)) {
        return New-ApiResult -Success $false -Message "Missing X-Loc-Timestamp header" -StatusCode 401
    }
    if ([string]::IsNullOrWhiteSpace($signature)) {
        return New-ApiResult -Success $false -Message "Missing X-Loc-Signature header" -StatusCode 401
    }

    $secret = Get-LocFleetAgentSecret -AgentId $agentId
    if (-not $secret) {
        return New-ApiResult -Success $false -Message "Unknown or revoked agent" -StatusCode 403
    }

    $tsValue = 0L
    if (-not [long]::TryParse($timestamp, [ref]$tsValue)) {
        return New-ApiResult -Success $false -Message "Invalid timestamp" -StatusCode 401
    }

    $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $skew = [Math]::Abs($nowUnix - $tsValue)
    if ($skew -gt $MaxSkewSeconds) {
        return New-ApiResult -Success $false -Message "Timestamp skew too large ($skew s)" -StatusCode 401
    }

    $path = $Request.Url.AbsolutePath
    $method = $Request.HttpMethod.ToUpperInvariant()
    if ($null -eq $Body) { $Body = "" }
    $payload = "$timestamp$method$path$Body"
    $expected = Get-LocHmacHex -Secret $secret -Message $payload

    if ($signature.ToLowerInvariant() -ne $expected) {
        return New-ApiResult -Success $false -Message "Invalid signature" -StatusCode 403
    }

    return New-ApiResult -Success $true -Message "OK" -Data @{ AgentId = $agentId }
}
