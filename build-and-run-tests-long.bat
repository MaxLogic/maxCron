@echo off
setlocal
chcp 65001 >nul
if /I "%~1"=="fpc" goto fpc
if not "%~1"=="" goto selection_error
if not "%1"=="" goto selection_error
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\Run-LongRoster.ps1"
exit /b %ERRORLEVEL%
:fpc
if not "%~2"=="" goto selection_error
if not "%2"=="" goto selection_error
set "MAXCRON_LONG_TESTS=1"
call "%~dp0build-and-run-tests-fpc.bat"
exit /b %ERRORLEVEL%
:selection_error
powershell.exe -NoProfile -NonInteractive -File "%~dp0tests\Reject-RosterSelection.ps1"
exit /b %ERRORLEVEL%
