#!/usr/bin/env python3
"""Small UTF-8 file backend for CitronOS TextEdit."""
from __future__ import annotations
import json
import pathlib
import sys

def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in {"read", "write"}:
        return 2
    path = pathlib.Path(sys.argv[2]).expanduser()
    try:
        if sys.argv[1] == "read":
            if not path.exists():
                print(json.dumps({"ok": True, "text": "", "path": str(path)}))
                return 0
            if path.is_dir():
                raise IsADirectoryError(str(path))
            text = path.read_text(encoding="utf-8", errors="replace")
            print(json.dumps({"ok": True, "text": text, "path": str(path)}))
            return 0

        path.parent.mkdir(parents=True, exist_ok=True)
        text = sys.stdin.read()
        tmp = path.with_name("." + path.name + ".golden-gate.tmp")
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)
        print(json.dumps({"ok": True, "path": str(path)}))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "path": str(path)}))
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
