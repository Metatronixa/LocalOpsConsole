# core/Cache.ps1 - In-memory TTL cache

$script:LocCache = @{}
$script:LocCacheLock = New-Object object

function Get-CacheKey {
    param([string]$Module, [string]$Kind, [string]$Action, [string]$ParamKey = "")
    return ("{0}:{1}:{2}:{3}" -f $Module.ToLower(), $Kind.ToLower(), $Action.ToLower(), $ParamKey).ToLower()
}

function Get-LocCache {
    param([string]$Key)

    $item = $null
    [System.Threading.Monitor]::Enter($script:LocCacheLock)
    try {
        if ($script:LocCache.ContainsKey($Key)) {
            $item = $script:LocCache[$Key]
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LocCacheLock)
    }

    if ($null -eq $item) { return $null }
    if ((Get-Date) -gt $item.Expires) {
        Remove-LocCache -Key $Key
        return $null
    }
    return $item.Value
}

function Set-LocCache {
    param(
        [string]$Key,
        [object]$Value,
        [int]$TtlSeconds = 20
    )

    if ($TtlSeconds -le 0) { return }

    $entry = [PSCustomObject]@{
        Value   = $Value
        Expires = (Get-Date).AddSeconds($TtlSeconds)
    }

    [System.Threading.Monitor]::Enter($script:LocCacheLock)
    try {
        $script:LocCache[$Key] = $entry
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LocCacheLock)
    }
}

function Remove-LocCache {
    param([string]$Key)

    [System.Threading.Monitor]::Enter($script:LocCacheLock)
    try {
        if ($script:LocCache.ContainsKey($Key)) {
            $script:LocCache.Remove($Key)
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LocCacheLock)
    }
}

function Clear-LocCache {
    param([string]$Prefix = $null)

    [System.Threading.Monitor]::Enter($script:LocCacheLock)
    try {
        if ([string]::IsNullOrWhiteSpace($Prefix)) {
            $script:LocCache = @{}
        }
        else {
            $keys = @($script:LocCache.Keys | Where-Object { $_.StartsWith($Prefix.ToLower()) })
            foreach ($k in $keys) { $script:LocCache.Remove($k) }
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LocCacheLock)
    }
}

function Get-OrSet-LocCache {
    param(
        [string]$Key,
        [int]$TtlSeconds,
        [scriptblock]$Factory
    )

    $cached = Get-LocCache -Key $Key
    if ($null -ne $cached) { return $cached }

    $value = & $Factory
    Set-LocCache -Key $Key -Value $value -TtlSeconds $TtlSeconds
    return $value
}
