@echo off
setlocal
chcp 65001 >nul


pushd "%~dp0"
if errorlevel 1 exit /b 1

set "MAXCRON_BUILD_CONFIG=release"
if /I "%MAXCRON_DEBUG_SAFETY%"=="1" set "MAXCRON_BUILD_CONFIG=debug"

rem An explicit override is authoritative, including an invalid path.
if defined DAK_EXE goto dak_resolved
for %%I in (DelphiAIKit.exe) do set "DAK_EXE=%%~$PATH:I"
if defined DAK_EXE goto dak_resolved
rem Standard sibling checkout layout; no persistent environment changes.
set "DAK_EXE=%~dp0..\..\DelphiAiKit\bin\DelphiAIKit.exe"

:dak_resolved
if not exist "%DAK_EXE%" (
  echo ERROR: DelphiAIKit.exe not found at "%DAK_EXE%". Set DAK_EXE to its absolute path. 1>&2
  set "EXITCODE=2"
  goto finish
)

"%DAK_EXE%" build --project "demo\CronDemo.dproj" --delphi 23.0 --platform Win32 --config %MAXCRON_BUILD_CONFIG% --show-warnings --show-hints --max-findings 1000
if not "%ERRORLEVEL%"=="0" goto failed

"%DAK_EXE%" build --project "tests\maxCronStressTests.dproj" --delphi 23.0 --platform Win32 --config %MAXCRON_BUILD_CONFIG% --show-warnings --show-hints --max-findings 1000
if not "%ERRORLEVEL%"=="0" goto failed

"%DAK_EXE%" build --project "tests\maxCronTests.dproj" --delphi 23.0 --platform Win32 --config %MAXCRON_BUILD_CONFIG% --show-warnings --show-hints --max-findings 1000
if not "%ERRORLEVEL%"=="0" goto failed

"%DAK_EXE%" build --project "tests\maxCronVclTests.dproj" --delphi 23.0 --platform Win32 --config %MAXCRON_BUILD_CONFIG% --show-warnings --show-hints --max-findings 1000
if not "%ERRORLEVEL%"=="0" goto failed

call tests\maxCronStressTests.exe %*
if not "%ERRORLEVEL%"=="0" goto failed

call tests\maxCronTests.exe %*
if not "%ERRORLEVEL%"=="0" goto failed

call tests\maxCronVclTests.exe %*
if not "%ERRORLEVEL%"=="0" goto failed

set "EXITCODE=0"
goto finish

:failed
set "EXITCODE=%ERRORLEVEL%"

:finish
popd
exit /b %EXITCODE%
