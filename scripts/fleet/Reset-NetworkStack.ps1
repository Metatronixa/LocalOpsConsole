# Reset-NetworkStack.ps1 - WARNING: resets Winsock and TCP/IP stack (requires reboot)
Write-Warning "This script resets Winsock and TCP/IP. A reboot is recommended afterward."
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
Write-Output "Network stack reset initiated. Reboot recommended."
