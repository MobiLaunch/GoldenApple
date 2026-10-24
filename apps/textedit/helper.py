#!/usr/bin/env python3
"""Small UTF-8 file backend for CitronOS TextEdit."""
from __future__ import annotations
import json
import os
import pathlib
import stat
import sys
import tempfile

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
            text = path.read_text(encoding="utf-8")
            print(json.dumps({"ok": True, "text": text, "path": str(path)}))
            return 0

        # Resolve a link before replacing its target, so saving does not break
        # a user's symlink. A unique same-directory temp avoids concurrent saves
        # colliding and preserves an existing private document's permissions.
        path = path.resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        text = sys.stdin.read()
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
        fd, name = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
        tmp = pathlib.Path(name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), mode)
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)
        print(json.dumps({"ok": True, "path": str(path)}))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "path": str(path)}))
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
