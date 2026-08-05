# Flush-DnsCache.ps1 - Clear the local DNS resolver cache
ipconfig /flushdns | Out-Null
Clear-DnsClientCache -ErrorAction SilentlyContinue
Write-Output "DNS cache flushed."
