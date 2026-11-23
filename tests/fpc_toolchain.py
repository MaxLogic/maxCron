"""Locate the Windows x64 toolchain selected by MAXCRON_FPC."""
import os
from pathlib import Path


def get_fpc_command():
    setting = os.environ.get('MAXCRON_FPC', '')
    hint = 'Set MAXCRON_FPC to the path to fpc.exe.'
    if not setting.strip():
        raise RuntimeError(hint)
    compiler = Path(os.path.abspath(setting))
    if not compiler.is_file():
        raise RuntimeError(f'FPC compiler does not exist: {compiler}. {hint}')
    if compiler.suffix.lower() != '.exe':
        raise RuntimeError(f'FPC compiler must be a native .exe. {hint}')
    bin_dir = compiler.parent
    config = bin_dir / 'fpc.cfg'
    units = bin_dir.parent.parent / 'units' / 'x86_64-win64'
    return [str(compiler), '-n', f'@{config}', f'-FD{bin_dir}', f'-Fu{units / "*"}']
