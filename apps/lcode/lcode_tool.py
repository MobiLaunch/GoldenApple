#!/usr/bin/env python3
"""Small build steps LCode runs as programs, so they stream and cancel like
any compiler:

    lcode_tool.py check ROOT          compile every Python file; problems as path:line:col: error: …
    lcode_tool.py test ROOT           pytest when installed, otherwise unittest discovery
    lcode_tool.py clean-python ROOT   remove __pycache__ folders
    lcode_tool.py rmtree PATH…        remove build folders
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys

SKIP = {".git", ".build", "build", "target", "venv", ".venv", "__pycache__", "node_modules"}


def python_files(root: str) -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP and not d.startswith("."))
        out += [os.path.join(dirpath, f) for f in sorted(filenames) if f.endswith(".py")]
    return out


def check(root: str) -> int:
    files = python_files(root)
    errors = 0
    for i, path in enumerate(files, 1):
        print(f"[{i}/{len(files)}] Checking {os.path.relpath(path, root)}", flush=True)
        try:
            with open(path, encoding="utf-8") as fh:
                source = fh.read()
            compile(source, path, "exec")
        except SyntaxError as exc:
            errors += 1
            print(f"{path}:{exc.lineno or 1}:{exc.offset or 1}: error: {exc.msg}", flush=True)
        except (OSError, UnicodeDecodeError, ValueError) as exc:
            errors += 1
            print(f"{path}:1:1: error: {exc}", flush=True)
    if not errors:
        try:
            import pyflakes  # noqa: F401  (optional: unused imports and undefined names)
        except ImportError:
            pass
        else:
            p = subprocess.run([sys.executable, "-m", "pyflakes", *files], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in p.stdout.splitlines():
                parts = line.split(":", 3)
                if len(parts) == 4 and parts[1].isdigit():
                    col = parts[2] if parts[2].strip().isdigit() else "1"
                    severity = "error" if "undefined name" in parts[3] else "warning"
                    errors += severity == "error"
                    print(f"{parts[0]}:{parts[1]}:{col}: {severity}: {parts[3].strip()}", flush=True)
    print("Build complete!" if not errors else f"{errors} error{'s' if errors != 1 else ''}", flush=True)
    return 1 if errors else 0


def test(root: str) -> int:
    try:
        import pytest  # noqa: F401
        argv = [sys.executable, "-m", "pytest", "-q"]
    except ImportError:
        start = "tests" if os.path.isdir(os.path.join(root, "tests")) else "."
        argv = [sys.executable, "-m", "unittest", "discover", "-v", "-s", start, "-t", "."]
    return subprocess.call(argv, cwd=root)


def clean_python(root: str) -> int:
    for dirpath, dirnames, _ in os.walk(root):
        for d in list(dirnames):
            if d == "__pycache__":
                shutil.rmtree(os.path.join(dirpath, d), ignore_errors=True)
                dirnames.remove(d)
    print("Removed cached bytecode.")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "check":
        return check(argv[2])
    if len(argv) >= 3 and argv[1] == "test":
        return test(argv[2])
    if len(argv) >= 3 and argv[1] == "clean-python":
        return clean_python(argv[2])
    if len(argv) >= 2 and argv[1] == "rmtree":
        for path in argv[2:]:
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
                print(f"Removed {path}")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
