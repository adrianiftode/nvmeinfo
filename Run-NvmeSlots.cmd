@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-NvmeSlots.ps1" %*
if not "%errorlevel%"=="0" pause
endlocal
