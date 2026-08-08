# Safe empty-catch / trailing-whitespace repair for PSScriptAnalyzer.
# IMPORTANT: never put `$_` in a [regex]::Replace replacement *string* — in .NET
# `$_` means "entire input". Use a MatchEvaluator scriptblock instead.
[CmdletBinding()]
param(
    [string[]]$Path = @('api', 'core', 'agent', 'modules', 'tools', 'scripts', 'tests')
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Settings = Join-Path $Root 'PSScriptAnalyzerSettings.psd1'
Import-Module PSScriptAnalyzer -ErrorAction Stop

$scanRoots = $Path | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path $_ }
$all = @()
foreach ($p in $scanRoots) {
    $all += @(Invoke-ScriptAnalyzer -Path $p -Recurse -Settings $Settings -ErrorAction SilentlyContinue)
}

$emptyFiles = @($all | Where-Object { $_.RuleName -eq 'PSAvoidUsingEmptyCatchBlock' } | Select-Object -ExpandProperty ScriptPath -Unique)
$wsFiles = @($all | Where-Object { $_.RuleName -eq 'PSAvoidTrailingWhitespace' } | Select-Object -ExpandProperty ScriptPath -Unique)

$catchFixed = 0
$wsFixed = 0
$pattern = [regex]'catch\s*\{(?:[\s\r\n]|\#[^\r\n]*)*\}'
$evaluator = {
    param($match)
    $null = $match
    'catch { Write-Debug $_.Exception.Message }'
}

foreach ($f in $emptyFiles) {
    $text = [IO.File]::ReadAllText($f)
    $newText = $pattern.Replace($text, $evaluator)
    if ($newText -ne $text) {
        if ($newText.Contains('catch { Write-Debug ') -and $newText.Length -gt ($text.Length * 2)) {
            Write-Error "Refusing to write $f - replacement ballooned (regex bug)"
        }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($f, $newText, $utf8)
        $catchFixed++
        Write-Host "catch  $f"
    }
}

foreach ($f in $wsFiles) {
    $lines = [IO.File]::ReadAllLines($f)
    $changed = $false
    $newLines = foreach ($line in $lines) {
        $t = $line.TrimEnd(" `t".ToCharArray())
        if ($t -cne $line) { $changed = $true }
        $t
    }
    if ($changed) {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllLines($f, @($newLines), $utf8)
        $wsFixed++
        Write-Host "ws     $f"
    }
}

Write-Host ""
Write-Host "Empty-catch files fixed: $catchFixed / $($emptyFiles.Count)"
Write-Host "Trailing-ws files fixed: $wsFixed / $($wsFiles.Count)"

$left = @()
foreach ($p in $scanRoots) {
    $left += @(Invoke-ScriptAnalyzer -Path $p -Recurse -Settings $Settings -ErrorAction SilentlyContinue |
        Where-Object { $_.RuleName -eq 'PSAvoidUsingEmptyCatchBlock' })
}
Write-Host "Remaining empty catch: $($left.Count)"
$left | Select-Object -First 15 | ForEach-Object { Write-Host ("  {0}:{1}" -f $_.ScriptPath, $_.Line) }
