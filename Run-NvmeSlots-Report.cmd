@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-NvmeSlots.ps1" -Html "%CD%\NvmeSlotReport.html" -Open %*
if not "%errorlevel%"=="0" pause
endlocal
