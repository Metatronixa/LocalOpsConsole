# Restart-PrintSpooler.ps1 - Restart the Windows Print Spooler service
Restart-Service -Name Spooler -Force -ErrorAction Stop
Write-Output "Print Spooler restarted successfully."
