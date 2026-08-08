@echo off
cd /d "%~dp0"
REM Headless launch — console only appears if start.ps1 surfaces a failure dialog.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0start.ps1"
exit /b %ERRORLEVEL%
