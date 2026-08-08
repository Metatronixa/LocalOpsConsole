# api/routers/ThreatRouter.ps1 - HMAC ingest for POST /api/v1/fleet/threat-telemetry
function Invoke-LocThreatTelemetryRoute {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string[]]$Segments
    )

    $request = $Context.Request
    $method = $request.HttpMethod.ToUpperInvariant()

    if (-not (Test-LocFleetEnabled)) {
        Send-JsonResponse -Context $Context -Success $false -Message 'Fleet is disabled' -StatusCode 503
        return
    }
    if ($method -ne 'POST') {
        Send-JsonResponse -Context $Context -Success $false -Message 'Threat telemetry requires POST' -StatusCode 405
        return
    }

    $body = Read-LocRequestBody -Request $request
    $parsed = Parse-LocJsonBody -Body $body
    if ($null -eq $parsed -and -not [string]::IsNullOrWhiteSpace($body)) {
        Send-JsonResponse -Context $Context -Success $false -Message 'Invalid JSON body' -StatusCode 400
        return
    }
    $bodyHash = if ($parsed) { $parsed } else { @{} }

    $auth = Test-LocAgentSignature -Request $request -Body $body
    if (-not $auth.Success) {
        $status = if ($auth.StatusCode) { [int]$auth.StatusCode } else { 401 }
        Send-JsonResponse -Context $Context -Success $false -Message $auth.Message -StatusCode $status
        return
    }
    $agentId = [string]$auth.Data.AgentId

    $result = Invoke-LocThreatTelemetryIngest -AgentId $agentId -Batch $bodyHash
    $status = if ($result.StatusCode) { [int]$result.StatusCode } else { 200 }
    Send-JsonResponse -Context $Context -Success $result.Success -Message $result.Message -Data $result.Data -StatusCode $status
}
