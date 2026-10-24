#!/usr/bin/env python3
"""Compile pinned Quartz implementation and AppKit enums; native CI uses same probe."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve() / 'src/external/cocotron'
lock = json.loads((ROOT / 'third_party/darling/source.lock.json').read_text())
paths = ['CoreGraphics/include/CoreGraphics/CGWindowLevel.h',
         'CoreGraphics/CGWindowLevel.m', 'AppKit/include/AppKit/NSWindow.h']
with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    for path in paths:
        target = temp / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(['git', 'show', lock['cocotron_commit'] + ':' + path], cwd=source))
    stub = temp / 'CoreGraphics/include/CoreFoundation/CoreFoundation.h'
    stub.parent.mkdir(parents=True)
    stub.write_text('#include <stdint.h>\n#define CF_ENUM(type, name) type name; enum\n'
                    '#define CF_IMPLICIT_BRIDGING_ENABLED\n#define CF_IMPLICIT_BRIDGING_DISABLED\n'
                    '#define COREGRAPHICS_EXPORT extern\n')
    appkit = (temp / paths[2]).read_text()
    start = appkit.index('enum {\n    NSNormalWindowLevel')
    end = appkit.index('};', start) + 2
    (temp / 'AppKitLevels.h').write_text(appkit[start:end])
    def run_probe():
        subprocess.run([os.environ.get('CC', 'cc'), '-x', 'c', '-I' + str(temp / 'CoreGraphics/include'),
                        '-I' + str(temp), str(temp / paths[1]), str(ROOT / 'tests/darling/window-levels.m'),
                        '-o', str(temp / 'probe')], check=True)
        return subprocess.run([str(temp / 'probe')], capture_output=True, text=True)
    baseline = run_probe()
    assert baseline.returncode != 0 and 'key=5 quartz=0 appkit=1 expected=3' in baseline.stderr, baseline.stderr
    patch = ROOT / 'third_party/darling/patches/0009-window-level-abi.patch'
    subprocess.run(['git', 'apply', str(patch)], cwd=temp, check=True)
    fixed = run_probe()
    assert fixed.returncode == 0, fixed.stderr
    print('Pinned baseline reproduces ABI mismatch; ' + fixed.stdout.strip())
