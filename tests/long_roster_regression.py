"""Compatibility view of the expanded native roster-contract regression."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    for name in ('repository', 'scratch', 'compiler', 'dunitx'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    args.scratch.mkdir(parents=True, exist_ok=False)
    routes = {'long-bat': 'delphi-bat', 'long-sh': 'delphi-sh', 'fpc-long-bat': 'fpc-bat', 'fpc-long-sh': 'fpc-sh'}
    native = args.scratch / 'all-families'
    command = [sys.executable, '-X', 'utf8=0', str(args.repository / 'tests/roster_contract_regression.py'), '--repository', str(args.repository), '--scratch', str(native), '--compiler', str(args.compiler), '--dunitx', str(args.dunitx), '--routes'] + list(routes)
    result = subprocess.run(command, check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError('Matrix infrastructure failure is not rejection proof')
    rows = json.loads((native / 'results.json').read_text(encoding='utf-8-sig'))
    selected = [{**row, 'route': routes[row['route']]} for row in rows if row['family'] == 'shared']
    (args.scratch / 'results.json').write_text(json.dumps(selected, indent=2), encoding='utf-8')
    return 0 if len(selected) == 24 and all(row['rejected'] for row in selected) else 1


if __name__ == '__main__':
    raise SystemExit(main())
