# core/Console.ps1 - Bridge helpers for UI console feed

function Get-ConsoleFeed {
    param([int]$Lines = 100)
    return Get-LocLogTail -Lines $Lines
}
