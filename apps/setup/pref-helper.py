#!/usr/bin/env python3
"""gg-pref: change one CitronOS desktop preference, checked and saved at once.

    gg-pref dotted.key JSON_VALUE     e.g. gg-pref dock.size 64
    gg-pref --check                   at login: put a damaged desktop.json back

Keys and their types are citronos/settings-schema.json's; a value that
doesn't fit is refused with the reason. Writers take turns under a lock, the
file is replaced whole, and the copy before each change is kept as
desktop.json.bak. A damaged desktop.json is put back from it, with a
notification saying so; with no good copy it's left as it is and the change
refused (exit 1, the reason on stderr).
"""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys

# The citronos package: beside the apps in the repository and a per-user
# install, with the shared UI in a system install.
HERE = Path(__file__).resolve()
for candidate in (HERE.parents[1] / "lib/python", HERE.parents[1] / "apps/lib/python",
                  Path("/usr/share/golden-gate/ui/python")):
    if (candidate / "citronos").is_dir():
        sys.path.insert(0, str(candidate))
        break
from citronos import settings  # noqa: E402


def tell(notice: str) -> None:
    if notice and shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "CitronOS", "-i", "dialog-information",
                        "Preferences restored", notice], timeout=5, check=False)


def main(argv: list[str]) -> int:
    store = settings.Store("desktop")
    try:
        if argv == ["--check"]:
            tell(store.check_file())
            return 0
        if len(argv) != 2:
            print("usage: gg-pref dotted.key JSON_VALUE | gg-pref --check", file=sys.stderr)
            return 2
        key, raw = argv
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            value = raw           # a bare word: a string
        store.set(key, value)
        tell(store.notice)
        return 0
    except settings.SettingsError as exc:
        print(f"desktop.json: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"desktop.json can't be saved ({exc.strerror or exc}).", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
