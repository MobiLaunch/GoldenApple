#!/usr/bin/env python3
"""Parse every native QML file without rewriting it or requiring Quickshell."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
formatter = shutil.which('pyside6-qmlformat') or shutil.which('qmlformat')
if not formatter:
    sys.exit('Install PySide6-Essentials or Qt qmlformat first.')
files = sorted(p for folder in ['apps', 'shell', 'themes', 'design/dist'] for p in (root / folder).rglob('*.qml'))
failures = []
for path in files:
    result = subprocess.run([formatter, str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        failures.append(str(path.relative_to(root)))
        print(result.stderr, file=sys.stderr)
print(f'QML syntax: {len(files) - len(failures)}/{len(files)} passed')
sys.exit(bool(failures))
