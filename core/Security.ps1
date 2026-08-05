# core/Security.ps1 - Elevation checks and path safety

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Require-Admin {
    param([string]$ActionName = "This action")

    if (-not (Test-IsAdmin)) {
        return New-ApiResult -Success $false -Message "$ActionName requires elevated (Administrator) privileges." -StatusCode 403 -Data @{
            RequiresAdmin = $true
            IsAdmin       = $false
        }
    }
    return $null
}

function Test-SafePath {
    param(
        [string]$CandidatePath,
        [string]$RootPath
    )

    $fullCandidate = [System.IO.Path]::GetFullPath($CandidatePath)
    $fullRoot = [System.IO.Path]::GetFullPath($RootPath)
    return $fullCandidate.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}
