@echo off
setlocal
chcp 65001 >nul
set "MAXCRON_STRESS=1"
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\Run-DefaultRoster.ps1" %*
exit /b %ERRORLEVEL%
