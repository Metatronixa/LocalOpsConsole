# Storage helpers
function ConvertTo-GB { param([double]$Bytes) [math]::Round($Bytes / 1GB, 2) }
