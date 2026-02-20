@echo off
REM Script Version 3

chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format o"') do set "BUILD_START=%%t"

rem =============================================================================
rem v 1.4.5
rem =============================================================================

rem ---- CONFIG (avoid rsvars collisions)
set "DEFAULT_VER=23"
set "DEFAULT_BUILD_CONFIG=Release"
set "DEFAULT_BUILD_PLATFORM=Win32"

set "ROOT=%CD%"
set "EXITCODE=0"

set "PROJECT="
set "VER=%DEFAULT_VER%"
set "BUILD_CONFIG=%DEFAULT_BUILD_CONFIG%"
set "BUILD_PLATFORM=%DEFAULT_BUILD_PLATFORM%"

:parse_args
if "%~1"=="" goto args_done

if /I "%~1"=="-ver" (
  if "%~2"=="" ( echo ERROR: -ver requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "VER=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-config" (
  if /I "%~2"=="Debug" ( set "BUILD_CONFIG=Debug" ) else if /I "%~2"=="Release" ( set "BUILD_CONFIG=Release" ) else (
    echo ERROR: -config must be Debug or Release.& set "EXITCODE=2" & goto usage_fail
  )
  shift & shift & goto parse_args
)
if /I "%~1"=="-platform" (
  if "%~2"=="" ( echo ERROR: -platform requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "BUILD_PLATFORM=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-keep-logs" set "KEEP_LOGS=1" & shift & goto parse_args
if /I "%~1"=="-show-warnings-on-success" set "SHOW_WARN_ON_SUCCESS=1" & shift & goto parse_args
if /I "%~1"=="-no-brand" set "NO_BRAND=1" & shift & goto parse_args

if not defined PROJECT (
  if exist "%~1" (
    set "PROJECT=%~1"
  ) else if exist "%~dp0%~1" (
    set "PROJECT=%~dp0%~1"
  ) else (
    echo ERROR: Project not found: %~1
    set "EXITCODE=2"
    goto usage_fail
  )
  shift & goto parse_args
)

shift & goto parse_args

:args_done
if not defined PROJECT (
  echo ERROR: No project ^(.dproj^) specified.
  set "EXITCODE=2"
  goto usage_fail
)

set "PRJ_NAME=%PROJECT%"
for %%p in ("%PROJECT%") do set "PROJECT=%%~fp"

rem ---- ASCII header (pipes escaped)
echo +================================================================================+
echo ^| BUILD   : %PRJ_NAME%
echo ^| PATH    : %PROJECT%
echo ^| CONFIG  : %BUILD_CONFIG%    PLATFORM: %BUILD_PLATFORM%    DELPHI: %VER%
echo +================================================================================+
echo.

rem ---- 1) Delphi root
set "BDS_ROOT="
if exist "C:\Program Files (x86)\Embarcadero\Studio\%VER%.0\bin\rsvars.bat" (
  set "BDS_ROOT=C:\Program Files (x86)\Embarcadero\Studio\%VER%.0"
) else if exist "C:\Program Files (x86)\Embarcadero\RAD Studio\%VER%.0\bin\rsvars.bat" (
  set "BDS_ROOT=C:\Program Files (x86)\Embarcadero\RAD Studio\%VER%.0"
) else (
  call :print_elapsed
  echo FAILED - Delphi %VER%.0 not found
  set "EXITCODE=1"
  goto cleanup
)
call "%BDS_ROOT%\bin\rsvars.bat"

rem ---- 2) MSBuild
set "MSBUILD="
if exist "%BDS_ROOT%\bin\msbuild.exe" set "MSBUILD=%BDS_ROOT%\bin\msbuild.exe"
if not defined MSBUILD (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%i in (`
      "%VSWHERE%" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe"
    `) do if not defined MSBUILD set "MSBUILD=%%i"
  )
)
if not defined MSBUILD if exist "%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe" set "MSBUILD=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
if not defined MSBUILD if exist "%WINDIR%\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"   set "MSBUILD=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
if not defined MSBUILD (
  call :print_elapsed
  echo FAILED - MSBuild.exe not found
  set "EXITCODE=1"
  goto cleanup
)

rem ---- 3) Logs
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
set "LOGDIR=%~dp0"
set "FULLLOG=%LOGDIR%build_%TS%.log"
set "OUTLOG=%LOGDIR%out_%TS%.log"
set "ERRLOG=%LOGDIR%errors_%TS%.log"

rem ---- 4) Build
set "ARGS=/t:Build /p:Config=%BUILD_CONFIG% /p:Platform=%BUILD_PLATFORM% /p:DCC_Quiet=true /p:DCC_UseMSBuildExternally=true /p:DCC_UseResponseFile=1 /p:DCC_UseCommandFile=1 /nologo /v:m /fl"
set "ARGS=%ARGS% /flp:logfile=%FULLLOG%;verbosity=normal"
set "ARGS=%ARGS% /flp1:logfile=%ERRLOG%;errorsonly;verbosity=quiet"

cmd /c ""%MSBUILD%" "%PROJECT%" %ARGS% > "%OUTLOG%" 2>&1"
set "RC=%ERRORLEVEL%"

rem ---- 5) Detect errors
set "ERRCOUNT=0"
set "HAS_ERRORS="

if exist "%ERRLOG%" for %%A in ("%ERRLOG%") do if %%~zA GTR 0 set "HAS_ERRORS=1"

if not defined HAS_ERRORS if not "%RC%"=="0" (
  for /f %%E in ('findstr /I /C:": error " /C:": fatal " "%OUTLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
  if not "!ERRCOUNT!"=="0" set "HAS_ERRORS=1"
)

if defined HAS_ERRORS (
  if exist "%ERRLOG%" (
    if "!ERRCOUNT!"=="0" for /f %%E in ('type "%ERRLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
    echo(
    call :print_elapsed
    echo Build FAILED. Errors: !ERRCOUNT!
    call :print_sanitized "%ERRLOG%"
  ) else (
    echo(
    call :print_elapsed
    echo Build FAILED. No error log generated.
    call :print_sanitized "%OUTLOG%"
  )
  set "EXITCODE=1"
  goto cleanup
)

rem ---- 6) Success
set "WARNCOUNT=0"
set "HINTCOUNT=0"

for /f %%H in ('
  findstr /I /C:": hint " /C:" hint warning " "%OUTLOG%" ^| find /c /v ""
') do set "HINTCOUNT=%%H"

for /f %%W in ('
  findstr /I /C:": warning " "%OUTLOG%" ^| findstr /I /V /C:" hint warning " ^| find /c /v ""
') do set "WARNCOUNT=%%W"

if defined SHOW_WARN_ON_SUCCESS (
  call :print_sanitized "%OUTLOG%"
  echo(
  call :print_elapsed
  echo SUCCESS. Warnings: !WARNCOUNT!, Hints: !HINTCOUNT!
) else (
  call :print_sanitized_filtered "%OUTLOG%"
  echo(
  call :print_elapsed
  echo SUCCESS.
)

set "EXITCODE=0"
goto cleanup

:usage_fail
echo.
echo Usage: %~nx0 ^<project.dproj^> [-ver N] [-config Debug^|Release] [-platform Platform] [-keep-logs] [-show-warnings-on-success] [-no-brand]
goto cleanup

:print_elapsed
for /f %%t in ('powershell -NoProfile -Command "$s=[datetime]::Parse('%BUILD_START%'); ((Get-Date) - $s).ToString('hh\:mm\:ss\.fff')"') do set "ELAPSED=%%t"
echo done in !ELAPSED!
exit /b 0

:print_sanitized
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } else { $s } }"
endlocal & exit /b 0

:print_sanitized_filtered
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ':\s+warning ' -or $s -match ' hint warning ' -or $s -match ':\s+hint ') { } else { $s } }"
endlocal & exit /b 0

:cleanup
if defined KEEP_LOGS (
  echo (Logs kept due to -keep-logs)
) else (
  if defined FULLLOG if exist "%FULLLOG%" del /q "%FULLLOG%" >nul 2>&1
  if defined OUTLOG  if exist "%OUTLOG%"  del /q "%OUTLOG%"  >nul 2>&1
  if defined ERRLOG  if exist "%ERRLOG%"  del /q "%ERRLOG%"  >nul 2>&1
)
set "code=%EXITCODE%"
popd
endlocal & exit /b %code%
