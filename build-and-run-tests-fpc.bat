@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\fpc\Run-FpcGate.ps1"
