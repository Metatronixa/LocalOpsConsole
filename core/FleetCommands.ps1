# core/FleetCommands.ps1 - Queue commands and running/pending timeouts

function Queue-LocFleetCommand {
    param(
        [Parameter(Mandatory)] [string]$AgentId,
        [Parameter(Mandatory)] [string]$Type,
        [object]$Payload = $null
    )

    if ($script:LocFleetCommandTypes -notcontains $Type) {
        return New-ApiResult -Success $false -Message "Invalid command type: $Type" -StatusCode 400
    }

    $agent = Get-LocFleetAgentRecord -AgentId $AgentId
    if (-not $agent -or $agent.Revoked) {
        return New-ApiResult -Success $false -Message "Agent not found" -StatusCode 404
    }

    $payloadHash = @{}
    if ($null -ne $Payload) {
        if ($Payload -is [hashtable]) {
            $payloadHash = @{} + $Payload
        }
        elseif ($Payload -is [PSCustomObject]) {
            foreach ($p in $Payload.PSObject.Properties) { $payloadHash[$p.Name] = $p.Value }
        }
    }

    if ($Type -eq 'InstallPackage') {
        $pkgId = if ($payloadHash.PackageId) { [string]$payloadHash.PackageId } else { '' }
        if ([string]::IsNullOrWhiteSpace($pkgId)) {
            return New-ApiResult -Success $false -Message 'PackageId required' -StatusCode 400
        }
        $pkg = Get-LocFleetPackageById -PackageId $pkgId
        if (-not $pkg) {
            return New-ApiResult -Success $false -Message "Unknown package: $pkgId" -StatusCode 400
        }
        $payloadHash.PackageId = [string]$pkg.Id
        $payloadHash.Name = [string]$pkg.Name
        $src = Get-LocFleetPackageSource -Package $pkg
        $payloadHash.Source = $src
        if ($pkg.WingetId) { $payloadHash.WingetId = [string]$pkg.WingetId }
        if ($pkg.Url) { $payloadHash.Url = [string]$pkg.Url }
        if ($pkg.SilentArgs) { $payloadHash.SilentArgs = [string]$pkg.SilentArgs }
        if ($pkg.Sha256) { $payloadHash.Sha256 = [string]$pkg.Sha256 }
        if ($pkg.FileName) { $payloadHash.FileName = [string]$pkg.FileName }
        if ($src -eq 'local') {
            $payloadHash.LocalSource = $true
            if ([string]::IsNullOrWhiteSpace([string]$pkg.FileName)) {
                return New-ApiResult -Success $false -Message "Local package $pkgId is missing FileName" -StatusCode 400
            }
            $pkgDir = Join-Path (Get-LocFleetSoftwareDir) ([string]$pkg.Id)
            $safeName = Resolve-LocFleetInstallerFileName -FileName ([string]$pkg.FileName)
            if (-not $safeName) {
                return New-ApiResult -Success $false -Message "Invalid FileName for package $pkgId" -StatusCode 400
            }
            $installerPath = Join-Path $pkgDir $safeName
            if (-not (Test-Path -LiteralPath $installerPath)) {
                return New-ApiResult -Success $false -Message "Installer missing on console: data/fleet/software/$($pkg.Id)/$safeName" -StatusCode 400
            }
        }
    }

    if ($Type -eq 'ApplySecurityPolicy') {
        $packId = if ($payloadHash.PackId) { [string]$payloadHash.PackId } else { 'hardening-basic' }
        $pack = Get-LocFleetPolicyPackById -PackId $packId
        if (-not $pack) {
            return New-ApiResult -Success $false -Message "Unknown policy pack: $packId" -StatusCode 400
        }
        $payloadHash.PackId = [string]$pack.id
        $payloadHash.PackName = [string]$pack.name
        $payloadHash.PackVersion = [string]$pack.version
        $payloadHash.ControlIds = @($pack.controls | ForEach-Object { [string]$_.id })
    }

    if ($Type -eq 'ModuleAction') {
        if (-not $payloadHash.ContainsKey('targetAgentId') -or [string]::IsNullOrWhiteSpace([string]$payloadHash['targetAgentId'])) {
            $payloadHash['targetAgentId'] = $AgentId
        }
        if (-not $payloadHash.ContainsKey('transactionId') -or [string]::IsNullOrWhiteSpace([string]$payloadHash['transactionId'])) {
            $payloadHash['transactionId'] = [guid]::NewGuid().ToString()
        }
        $payloadCheck = Test-LocAgentExecutionPayload -Payload $payloadHash
        if (-not $payloadCheck.Success) {
            return $payloadCheck
        }
        foreach ($k in @('transactionId', 'targetAgentId', 'module', 'action', 'riskLevel')) {
            $payloadHash[$k] = $payloadCheck.Data.$k
        }
        if ($null -ne $payloadCheck.Data.parameters) {
            $payloadHash['parameters'] = $payloadCheck.Data.parameters
        }
        $payloadHash['requiresApproval'] = [bool]$payloadCheck.Data.requiresApproval
    }

    if ($Type -eq 'InstallRustDesk') {
        try {
            $settings = Get-LocSettings
            $url = if ($settings.PSObject.Properties['rustDeskInstallerUrl']) { [string]$settings.rustDeskInstallerUrl } else { '' }
            $sha = if ($settings.PSObject.Properties['rustDeskInstallerSha256']) { [string]$settings.rustDeskInstallerSha256 } else { '' }
            $silent = if ($settings.PSObject.Properties['rustDeskSilentArgs']) { [string]$settings.rustDeskSilentArgs } else { '/S' }
            if ([string]::IsNullOrWhiteSpace($url)) {
                return New-ApiResult -Success $false -Message 'rustDeskInstallerUrl is not set in settings.json' -StatusCode 400
            }
            if ($url -notmatch '^https://') {
                return New-ApiResult -Success $false -Message 'rustDeskInstallerUrl must be HTTPS' -StatusCode 400
            }
            $payloadHash.InstallerUrl = $url.Trim()
            if (-not [string]::IsNullOrWhiteSpace($sha)) { $payloadHash.InstallerSha256 = $sha.Trim() }
            if ([string]::IsNullOrWhiteSpace($silent)) { $silent = '/S' }
            $payloadHash.SilentArgs = $silent.Trim()
        }
        catch {
            return New-ApiResult -Success $false -Message $_.Exception.Message -StatusCode 500
        }
    }

    $cmdId = [guid]::NewGuid().ToString("N")
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $cmd = [ordered]@{
        Id          = $cmdId
        AgentId     = $AgentId
        Type        = $Type
        Payload     = $payloadHash
        Status      = "Pending"
        CreatedAt   = $now
        ClaimedAt   = $null
        CompletedAt = $null
        Result      = $null
    }

    Invoke-LocFleetFileLock -Name "commands" -Action {
        $data = Read-LocFleetJson -FileName "commands.json" -Default @{ commands = @() }
        $list = @()
        if ($data.commands) { $list = @($data.commands) }
        $list += $cmd
        Write-LocFleetJson -FileName "commands.json" -Data @{ commands = $list }
    }

    Add-LocFleetAudit -Action "CommandQueued" -AgentId $AgentId -Detail @{ CommandId = $cmdId; Type = $Type; Payload = $Payload }
    Write-LocLog -Module "FLEET" -Action "QueueCommand" -Level "INFO" -Message "$Type queued for $AgentId ($cmdId)"

    return New-ApiResult -Success $true -Message "Command queued" -Data $cmd
}

# Running jobs older than this are treated as abandoned (agent never posted a result).
$script:LocFleetRunningTimeoutMinutes = 45
$script:LocFleetShortRunningTimeoutMinutes = 5
$script:LocFleetPendingNeverClaimedMinutes = 10
$script:LocFleetLongCommandTypes = @(
    'SfcScannow', 'ChkdskScan', 'ChkdskScheduleFix',
    'InstallWindowsUpdates', 'ApplySecurityPolicy', 'InstallPackage', 'SelfUpdate'
)

function Get-LocFleetRunningTimeoutMinutes {
    param([string]$Type)
    if ($script:LocFleetLongCommandTypes -contains [string]$Type) {
        return [int]$script:LocFleetRunningTimeoutMinutes
    }
    return [int]$script:LocFleetShortRunningTimeoutMinutes
}

function Test-LocFleetCommandStaleRunning {
    param(
        [object]$Command,
        [datetime]$Now = $(Get-Date),
        [int]$TimeoutMinutes = 0
    )
    if (-not $Command) { return $false }
    if ([string]$Command.Status -ne "Running") { return $false }
    if ($TimeoutMinutes -lt 1) {
        $TimeoutMinutes = Get-LocFleetRunningTimeoutMinutes -Type ([string]$Command.Type)
    }
    $claimedRaw = [string]$Command.ClaimedAt
    if ([string]::IsNullOrWhiteSpace($claimedRaw)) {
        $claimedRaw = [string]$Command.CreatedAt
    }
    $claimedAt = [datetime]::MinValue
    if (-not [datetime]::TryParse($claimedRaw, [ref]$claimedAt)) { return $false }
    return (($Now - $claimedAt).TotalMinutes -ge $TimeoutMinutes)
}

function Test-LocFleetCommandStalePending {
    param(
        [object]$Command,
        [datetime]$Now = $(Get-Date),
        [int]$TimeoutMinutes = 0
    )
    if (-not $Command) { return $false }
    if ([string]$Command.Status -ne "Pending") { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string]$Command.ClaimedAt)) { return $false }
    if ($TimeoutMinutes -lt 1) { $TimeoutMinutes = [int]$script:LocFleetPendingNeverClaimedMinutes }
    $createdRaw = [string]$Command.CreatedAt
    if ([string]::IsNullOrWhiteSpace($createdRaw)) { return $false }
    $createdAt = [datetime]::MinValue
    if (-not [datetime]::TryParse($createdRaw, [ref]$createdAt)) { return $false }
    return (($Now - $createdAt).TotalMinutes -ge $TimeoutMinutes)
}

