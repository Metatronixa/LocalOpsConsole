# EnvironmentProfileDetector.ps1 - Classify agent host environment profile
function Get-LocAgentEnvironmentProfile {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $allowed = @(
        'DomainController'
        'ActiveDirectoryMember'
        'EntraCloudJoined'
        'StandaloneWorkgroup'
    )

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $role = [int]$cs.DomainRole
        # 0 Standalone Workstation, 1 Member Workstation, 2 Standalone Server,
        # 3 Member Server, 4 Backup DC, 5 Primary DC
        if ($role -in @(4, 5)) { return 'DomainController' }
        if ($role -eq 3) { return 'ActiveDirectoryMember' }
        if ($role -eq 1 -and $cs.PartOfDomain) { return 'ActiveDirectoryMember' }
    }
    catch {
        Write-Debug $_.Exception.Message
    }

    try {
        $dsreg = & dsregcmd.exe /status 2>$null | Out-String
        if ($dsreg -match '(?im)AzureAdJoined\s*:\s*YES' -or $dsreg -match '(?im)WorkplaceJoined\s*:\s*YES') {
            return 'EntraCloudJoined'
        }
    }
    catch {
        Write-Debug $_.Exception.Message
    }

    return 'StandaloneWorkgroup'
}

# Allow direct invoke for gate checks
if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.') {
    Get-LocAgentEnvironmentProfile
}
