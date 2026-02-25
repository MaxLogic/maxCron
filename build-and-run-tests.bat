@echo off
setlocal
chcp 65001 >nul


pushd "%~dp0"

set "MAXCRON_BUILD_CONFIG=release"
if /I "%MAXCRON_DEBUG_SAFETY%"=="1" set "MAXCRON_BUILD_CONFIG=debug"

call build-delphi.bat demo\CronDemo.dproj -config %MAXCRON_BUILD_CONFIG% ^
  && call build-delphi.bat tests\maxCronStressTests.dproj -config %MAXCRON_BUILD_CONFIG% ^
  && call build-delphi.bat tests\maxCronTests.dproj -config %MAXCRON_BUILD_CONFIG% ^
  && call build-delphi.bat tests\maxCronVclTests.dproj -config %MAXCRON_BUILD_CONFIG% ^
  && call tests\maxCronStressTests.exe %* ^
  && call tests\maxCronTests.exe %* ^
  && call tests\maxCronVclTests.exe %*

rem Preserve the exit code (build or tests)
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
