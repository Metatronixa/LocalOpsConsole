@echo off
cd /d "%~dp0"
title LocalOpsConsole
echo Starting LocalOpsConsole...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
if errorlevel 1 (
  echo.
  echo Launch failed. If PowerShell is blocked, right-click start.bat and choose "Run as administrator".
  pause
)
