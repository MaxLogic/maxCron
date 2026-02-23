@echo off
setlocal
chcp 65001 >nul

pushd "%~dp0"

call build-delphi.bat benchmarks\maxCronBenchmarks.dproj -config release ^
  && call benchmarks\maxCronBenchmarks.exe %*

set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
