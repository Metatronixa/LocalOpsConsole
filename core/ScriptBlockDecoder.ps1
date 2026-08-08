# ScriptBlockDecoder.ps1 - Safe Base64 decode + threat keyword match (never executes code)
function Test-LocThreatBase64Candidate {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)(?:[A-Za-z0-9+/]{32,}={0,2})')
}

function ConvertFrom-LocThreatBase64Safe {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [PSCustomObject]@{ Decoded = ''; Matched = $false; Error = $null }
    }
    $candidates = [regex]::Matches($Text, '(?i)[A-Za-z0-9+/]{32,}={0,2}')
    foreach ($m in $candidates) {
        $b64 = $m.Value
        try {
            $bytes = [Convert]::FromBase64String($b64)
            # Prefer UTF8; fall back to Unicode if mostly NULs
            $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            if ($decoded -match '[\u0000]') {
                $decoded = [System.Text.Encoding]::Unicode.GetString($bytes)
            }
            # Reject binary garbage (too many control chars)
            $ctrl = ([regex]::Matches($decoded, '[\x00-\x08\x0B\x0C\x0E-\x1F]')).Count
            if ($ctrl -gt ([math]::Max(4, [int]($decoded.Length * 0.05)))) { continue }
            return [PSCustomObject]@{ Decoded = $decoded; Matched = $true; Error = $null }
        }
        catch {
            continue
        }
    }
    return [PSCustomObject]@{ Decoded = ''; Matched = $false; Error = 'No valid Base64 payload' }
}

function Get-LocThreatKeywordHits {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $patterns = @(
        @{ Name = 'Invoke-Expression'; Pattern = '(?i)\bInvoke-Expression\b|\bIEX\b' }
        @{ Name = 'DownloadString'; Pattern = '(?i)DownloadString|DownloadFile|WebClient' }
        @{ Name = 'Mimikatz'; Pattern = '(?i)mimikatz|sekurlsa|lsadump' }
        @{ Name = 'Add-MpPreference'; Pattern = '(?i)Add-MpPreference|Set-MpPreference|DisableRealtimeMonitoring' }
        @{ Name = 'EncodedCommand'; Pattern = '(?i)-enc(odedcommand)?\b|FromBase64String' }
        @{ Name = 'AMSI bypass'; Pattern = '(?i)amsiUtils|AmsiScanBuffer' }
    )
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($p in $patterns) {
        if ($Text -match $p.Pattern) { [void]$hits.Add([string]$p.Name) }
    }
    return @($hits | Select-Object -Unique)
}

function Invoke-LocScriptBlockDecode {
    param(
        [string]$RawText,
        [bool]$IsEncoded = $false
    )
    $raw = if ($null -eq $RawText) { '' } else { [string]$RawText }
    $decoded = $raw
    $didDecode = $false

    if ($IsEncoded -and -not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $bytes = [Convert]::FromBase64String($raw.Trim())
            $candidate = [System.Text.Encoding]::UTF8.GetString($bytes)
            if ($candidate -match '[\u0000]') {
                $candidate = [System.Text.Encoding]::Unicode.GetString($bytes)
            }
            $decoded = $candidate
            $didDecode = $true
        }
        catch {
            Write-Debug $_.Exception.Message
        }
    }

    if (-not $didDecode -and (Test-LocThreatBase64Candidate -Text $raw)) {
        $r = ConvertFrom-LocThreatBase64Safe -Text $raw
        if ($r.Matched -and $r.Decoded) {
            $decoded = [string]$r.Decoded
            $didDecode = $true
        }
    }
    $scan = if ($didDecode) { "$raw`n$decoded" } else { $raw }
    $keywords = @(Get-LocThreatKeywordHits -Text $scan)
    return [PSCustomObject]@{
        RawText     = $raw
        DecodedText = $decoded
        WasDecoded  = $didDecode
        KeywordHits = @($keywords)
        HighRisk    = ($keywords.Count -gt 0)
    }
}
