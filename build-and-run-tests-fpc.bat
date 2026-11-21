@echo off
setlocal DisableDelayedExpansion
if not "%~1"=="" goto selection_error
if not "%1"=="" goto selection_error
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\fpc\Run-FpcGate.ps1"
exit /b %ERRORLEVEL%
:selection_error
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\Reject-RosterSelection.ps1"
exit /b %ERRORLEVEL%
