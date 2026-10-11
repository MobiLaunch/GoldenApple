#!/usr/bin/env python3
"""Run unchanged PIP fixture with separate behavior and clean-exit gates.

A regular log file prevents Darling services retaining stdout from holding a
tee pipeline open after the fixture exits. A JSON pass cannot mask an exit hang.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location('gui', Path(__file__).with_name('test-gui.py'))
gui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gui)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    binary = args.app.resolve() / 'Contents/MacOS/PIPLab'
    prefix, output = args.prefix.resolve(), args.output.resolve()
    if prefix.exists() or not binary.is_file() or not os.environ.get('DISPLAY'):
        parser.error('Require a fresh prefix, PIPLab executable and DISPLAY')
    output.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, 'DPREFIX': str(prefix)}
    result = {'passed': False, 'phase': 'startup', 'launcher_exit': None}
    try:
        with (output / 'runtime.log').open('w') as log:
            process = subprocess.Popen(['darling', str(binary), '/Volumes/SystemRoot' + str(output / 'results.json')],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            result['phase'] = 'clean-exit'
            try:
                result['launcher_exit'] = process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                raise RuntimeError('PIP launcher did not exit within 30 seconds')
        result['phase'] = 'behavior'
        evidence = json.loads((output / 'results.json').read_text())
        result['behavior'] = evidence
        if result['launcher_exit'] != 0:
            raise RuntimeError(f"PIP exited with {result['launcher_exit']}")
        if not (evidence.get('passed') and evidence.get('checks', 0) > 0 and evidence.get('failures') == 0):
            raise RuntimeError('PIP behavior checks failed')
        result['passed'] = True
        result['phase'] = 'complete'
    except (OSError, RuntimeError, ValueError) as error:
        result['error'] = str(error)
        # Preserve completed checks independently of the exit result.
        try:
            result['behavior'] = json.loads((output / 'results.json').read_text())
        except (OSError, ValueError):
            pass
    finally:
        (output / 'runner-result.json').write_text(json.dumps(result, indent=2) + '\n')
        if not result['passed']:
            gui.capture_live_backtrace(output, binary)
        if prefix.exists():
            try:
                subprocess.run(['darling', 'shutdown'], env=env, capture_output=True, timeout=10)
            except (OSError, subprocess.TimeoutExpired) as error:
                result['cleanup_error'] = str(error)
        (output / 'runner-result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
