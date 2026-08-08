# RunAutomaticDiagnosis.ps1 — sequenced light checks
try {
    $checks = @()
    $adapter = Get-LocActiveAdapterInfo
    $gateway = if ($adapter) { $adapter.Gateway } else { Get-LocFirstIPv4DefaultGateway }

    $adapterOk = ($adapter -and $adapter.Status -eq 'Up')
    $checks += [PSCustomObject]@{ Name = "Adapter"; Passed = $adapterOk; Detail = if ($adapter) { $adapter.Name } else { "None" } }

    $dns = Invoke-LocDnsResolve -HostName "google.com" -TimeoutSec 2
    $checks += [PSCustomObject]@{ Name = "DNS"; Passed = $dns.Success; Detail = $dns.Address }

    $pingCf = Invoke-LocFastPing -Target "1.1.1.1" -Count 2 -TimeoutMs 1200
    $checks += [PSCustomObject]@{ Name = "Internet ping"; Passed = ($pingCf.LossPct -le 20); Detail = ("loss {0}%" -f $pingCf.LossPct) }

    $https = Invoke-LocHttpsHead -Url "https://www.microsoft.com" -TimeoutSec 2
    $checks += [PSCustomObject]@{ Name = "HTTPS"; Passed = $https.Success; Detail = $https.StatusCode }

    $gwPing = $null
    if ($gateway) {
        $gwPing = Invoke-LocFastPing -Target $gateway -Count 1 -TimeoutMs 1200
        $checks += [PSCustomObject]@{ Name = "Gateway"; Passed = $gwPing.Success; Detail = $gateway }
    }

    $proxy = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    $proxyOn = [bool]$proxy.ProxyEnable
    $checks += [PSCustomObject]@{ Name = "Proxy enabled"; Passed = (-not $proxyOn); Detail = if ($proxyOn) { $proxy.ProxyServer } else { "Off" } }

    $vpn = Get-VpnConnection -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionStatus -eq 'Connected' }
    $vpnConnected = @($vpn).Count -gt 0
    if ($vpnConnected) {
        $checks += [PSCustomObject]@{ Name = "VPN active"; Passed = $true; Detail = ($vpn | Select-Object -First 1).Name }
    }

    # Decision logic
    $diagnosis = "Internet connectivity appears healthy."
    $likelyCause = "No dominant failure pattern detected."
    $fixProb = 0.3
    $recommended = @()
    $decisionTable = @()

    if (-not $adapterOk) {
        $diagnosis = "Local network adapter is down or disconnected."
        $likelyCause = "Physical link, disabled adapter, or driver issue."
        $fixProb = 0.7
        $recommended += [PSCustomObject]@{ ActionId = "RestartAdapter"; Label = "Restart network adapter" }
        $recommended += [PSCustomObject]@{ ActionId = "EnableAdapter"; Label = "Enable adapter" }
        $decisionTable += [PSCustomObject]@{ Symptom = "Adapter down"; Cause = "Link/driver"; Confidence = 0.75; Fix = "RestartAdapter" }
    }
    elseif ($gateway -and $gwPing -and -not $gwPing.Success) {
        $diagnosis = "Cannot reach the default gateway."
        $likelyCause = "Local LAN, switch, AP, or cable issue."
        $fixProb = 0.65
        $recommended += [PSCustomObject]@{ ActionId = "ClearArp"; Label = "Clear ARP cache" }
        $recommended += [PSCustomObject]@{ ActionId = "RestartAdapter"; Label = "Restart adapter" }
        $decisionTable += [PSCustomObject]@{ Symptom = "Gateway unreachable"; Cause = "Local LAN"; Confidence = 0.7; Fix = "ClearArp" }
    }
    elseif (-not $dns.Success -and $pingCf.LossPct -le 10) {
        $diagnosis = "DNS resolution is failing while IP connectivity works."
        $likelyCause = "Misconfigured or unreachable DNS servers."
        $fixProb = 0.8
        $recommended += [PSCustomObject]@{ ActionId = "RegisterDns"; Label = "Register DNS (flush + register)" }
        $recommended += [PSCustomObject]@{ ActionId = "SetDnsCloudflare"; Label = "Set DNS to Cloudflare (1.1.1.1)" }
        $recommended += [PSCustomObject]@{ ActionId = "RestartDnsClient"; Label = "Restart DNS Client service" }
        $decisionTable += [PSCustomObject]@{ Symptom = "DNS fail, IP OK"; Cause = "DNS config"; Confidence = 0.85; Fix = "SetDnsCloudflare" }
    }
    elseif ($pingCf.LossPct -gt 20) {
        $diagnosis = "High packet loss to the internet."
        $likelyCause = "ISP path, Wi-Fi interference, or upstream congestion."
        $fixProb = 0.4
        $recommended += [PSCustomObject]@{ ActionId = "ResetTcpIp"; Label = "Reset TCP/IP stack" }
        $decisionTable += [PSCustomObject]@{ Symptom = "Packet loss"; Cause = "Path/RF"; Confidence = 0.55; Fix = "ResetTcpIp" }
    }
    elseif (-not $https.Success) {
        $diagnosis = "HTTPS to common sites is failing."
        $likelyCause = if ($proxyOn) { "Proxy or TLS interception." } else { "Firewall, proxy, or captive portal." }
        $fixProb = 0.6
        if ($proxyOn) {
            $recommended += [PSCustomObject]@{ ActionId = "ResetProxy"; Label = "Reset proxy settings" }
        }
        $recommended += [PSCustomObject]@{ ActionId = "ResetWinsock"; Label = "Reset Winsock catalog" }
        $decisionTable += [PSCustomObject]@{ Symptom = "HTTPS fail"; Cause = if ($proxyOn) { "Proxy" } else { "Firewall" }; Confidence = 0.65; Fix = "ResetProxy" }
    }
    elseif ($vpnConnected -and $pingCf.LossPct -gt 10) {
        $diagnosis = "VPN is connected and internet path shows degradation."
        $likelyCause = "VPN tunnel or split-tunnel routing."
        $fixProb = 0.5
        $decisionTable += [PSCustomObject]@{ Symptom = "VPN + loss"; Cause = "VPN tunnel"; Confidence = 0.6; Fix = "DisconnectVpn" }
    }

    if (-not $recommended.Count) {
        $recommended += [PSCustomObject]@{ ActionId = "RegisterDns"; Label = "Refresh DNS registration" }
    }

    Add-LocInternetEvent -Category "Diagnosis" -Severity "INFO" -Message $diagnosis -Detail $likelyCause

    return New-ApiResult -Success $true -Message $diagnosis -Data ([PSCustomObject]@{
        Diagnosis           = $diagnosis
        LikelyCause         = $likelyCause
        RecommendedActions  = @($recommended)
        FixProbability      = $fixProb
        DecisionTable       = @($decisionTable)
        Checks              = @($checks)
    })
}
catch {
    return New-ApiResult -Success $false -Message $_.Exception.Message
}
