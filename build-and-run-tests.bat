@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\Run-DefaultRoster.ps1" %*
exit /b %ERRORLEVEL%
