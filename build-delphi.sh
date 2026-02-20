#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BAT_PATH_WINDOWS="${MAXCRON_BAT_PATH_WINDOWS:-$(wslpath -w -a "$ROOT_DIR/build-delphi.bat")}"

args=()

if [ "$#" -gt 0 ]; then
  first="$1"
  if [[ "$first" == *.dproj || "$first" == *.dpr || "$first" == *.groupproj ]]; then
    if [[ "$first" == [A-Za-z]:* ]]; then
      proj_win="$first"
    else
      if [[ "$first" == /* ]]; then
        proj_path="$first"
      else
        proj_path="$ROOT_DIR/$first"
      fi
      proj_win="$(wslpath -w -a "$proj_path")"
    fi
    args+=("$proj_win")
    shift
  fi
fi

while [ "$#" -gt 0 ]; do
  args+=("$1")
  shift
done

run_bat_via_launcher() {
  local bat_path_windows="$1"
  shift

  local launcher_path launcher_path_windows
  launcher_path="$(mktemp "$ROOT_DIR/.wsl-bat-launcher.XXXXXX.cmd")"
  launcher_path_windows="$(wslpath -w -a "$launcher_path")"

  {
    printf '@echo off\r\n'
    printf 'setlocal DisableDelayedExpansion\r\n'

    local l_arg l_escaped l_idx
    l_idx=0
    for l_arg in "$@"; do
      if [[ "$l_arg" == *$'\n'* || "$l_arg" == *'"'* ]]; then
        printf 'echo ERROR: Argument contains unsupported character (newline or double quote).\r\n'
        printf 'exit /b 2\r\n'
        break
      fi
      l_idx=$((l_idx + 1))
      l_escaped=${l_arg//%/%%}
      printf 'set "ARG%d=%s"\r\n' "$l_idx" "$l_escaped"
    done

    printf 'call "%s"' "$bat_path_windows"
    local i
    for ((i = 1; i <= l_idx; i++)); do
      printf ' "%%ARG%d%%"' "$i"
    done
    printf '\r\n'
    printf 'set "EXITCODE=%%ERRORLEVEL%%"\r\n'
    printf 'endlocal ^& exit /b %%EXITCODE%%\r\n'
  } >"$launcher_path"

  local l_rc
  set +e
  /mnt/c/Windows/System32/cmd.exe /C "$launcher_path_windows"
  l_rc=$?
  set -e
  rm -f "$launcher_path"
  return "$l_rc"
}

run_bat_via_launcher "$BAT_PATH_WINDOWS" "${args[@]}"
