@echo off
cd /d "%~dp0"
REM Hidden-window launch (not appliance/API-only). Console appears only if start.ps1 surfaces a failure dialog.
REM For API-only: powershell -File start.ps1 -NoBrowser   or   -Appliance
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0start.ps1"
exit /b %ERRORLEVEL%
