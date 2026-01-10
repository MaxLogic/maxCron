@echo off
setlocal
chcp 65001 >nul

pushd "%~dp0"

set "MAXCRON_STRESS=1"

call build-delphi.bat tests\maxCronStressTests.dproj -config release ^
  && call build-delphi.bat tests\maxCronTests.dproj -config release ^
  && call build-delphi.bat tests\maxCronVclTests.dproj -config release ^
  && call tests\maxCronStressTests.exe %* ^
  && call tests\maxCronTests.exe %* ^
  && call tests\maxCronVclTests.exe %*

rem Preserve the exit code (build or tests)
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
