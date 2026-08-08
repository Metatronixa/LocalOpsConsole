# CapabilityDetector.ps1 - Detect agent capability tags for fleet routing

function Test-LocAgentWindowsFeature {
    param([string[]]$Name)
    foreach ($n in $Name) {
        try {
            $f = Get-WindowsFeature -Name $n -ErrorAction SilentlyContinue
            if ($f -and $f.InstallState -eq 'Installed') { return $true }
        }
        catch { }
        try {
            $opt = Get-WindowsOptionalFeature -Online -FeatureName $n -ErrorAction SilentlyContinue
            if ($opt -and $opt.State -eq 'Enabled') { return $true }
        }
        catch { }
    }
    return $false
}

function Test-LocAgentModulePresent {
    param([string[]]$Name)
    foreach ($n in $Name) {
        try {
            if (Get-Module -ListAvailable -Name $n -ErrorAction SilentlyContinue) { return $true }
        }
        catch { }
    }
    return $false
}

function Get-LocAgentCapabilities {
    <#
    .SYNOPSIS
      Returns capability tags such as AD_DS, DNS, DHCP, Hyper-V, GPO, Certificates, FileServer, ServerOperations.
    #>
    $tags = New-Object System.Collections.Generic.List[string]

    $isServer = $false
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.ProductType -and [int]$os.ProductType -ne 1) { $isServer = $true }
        elseif ($os -and [string]$os.Caption -match '(?i)Windows Server') { $isServer = $true }
    }
    catch { }

    $domainJoined = $false
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs -and [bool]$cs.PartOfDomain) { $domainJoined = $true }
    }
    catch { }

    # Certificates + ServerOperations: always available for ops console targets
    [void]$tags.Add('Certificates')
    [void]$tags.Add('ServerOperations')

    if ($domainJoined -or (Test-LocAgentModulePresent -Name @('ActiveDirectory'))) {
        if ($domainJoined -or (Test-LocAgentWindowsFeature -Name @('AD-Domain-Services')) -or
            (Test-LocAgentModulePresent -Name @('ActiveDirectory'))) {
            [void]$tags.Add('AD_DS')
        }
    }

    if ((Test-LocAgentWindowsFeature -Name @('DNS', 'DNS-Server')) -or
        (Test-LocAgentModulePresent -Name @('DnsServer'))) {
        [void]$tags.Add('DNS')
    }

    if ((Test-LocAgentWindowsFeature -Name @('DHCP', 'DHCP-Server')) -or
        (Test-LocAgentModulePresent -Name @('DhcpServer'))) {
        [void]$tags.Add('DHCP')
    }

    if ((Test-LocAgentWindowsFeature -Name @('Hyper-V')) -or
        (Test-LocAgentModulePresent -Name @('Hyper-V'))) {
        [void]$tags.Add('Hyper-V')
    }

    if ($domainJoined -or (Test-LocAgentModulePresent -Name @('GroupPolicy'))) {
        [void]$tags.Add('GPO')
    }

    if ($isServer -or (Test-LocAgentWindowsFeature -Name @('FS-FileServer', 'FileAndStorage-Services')) -or
        (Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('IPC$', 'ADMIN$', 'C$') } | Select-Object -First 1)) {
        [void]$tags.Add('FileServer')
    }
    elseif (-not $tags.Contains('FileServer')) {
        # Local workstation may still expose shares; AlwaysLocal hint from capabilities.json
        try {
            $local = @(Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('IPC$') })
            if ($local.Count -gt 0) { [void]$tags.Add('FileServer') }
        }
        catch { }
    }

    return @($tags | Select-Object -Unique)
}
