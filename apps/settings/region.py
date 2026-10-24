#!/usr/bin/env python3
"""Your region, its formats and what Setup Assistant put off, for Settings.

    region.py status                  {"ok", "region", "zone", "formats", "deferred": [...]}
    region.py set-formats LOCALE [REGION]
                                      dates, numbers, currency and measurement follow
                                      LOCALE (such as de_CH) from the next sign-in
    region.py set-zone ZONE           record the time zone (once timedatectl took it)
    region.py resolve ITEM            ITEM (timezone, formats, location) is done

Setup Assistant writes ~/.config/golden-gate/region.json ({"region", "zone",
"formats"}) and lists what it couldn't finish in setup-deferred.json. The
formats are LC_* variables in ~/.config/environment.d/90-golden-formats.conf;
the language (LANG) is a separate choice. Every change merges into the saved
record under one lock and is written atomically; finishing an item takes it
off the list (and the list goes once it's empty). Prints {"ok": …}."""
from __future__ import annotations

import fcntl
import json
import os
import pathlib
import re
import sys
import tempfile

CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")
GG = CONFIG / "golden-gate"
REGION = GG / "region.json"
DEFERRED = GG / "setup-deferred.json"
FORMATS = CONFIG / "environment.d/90-golden-formats.conf"
ITEMS = ("timezone", "formats", "location")
LC = ("LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_PAPER", "LC_MEASUREMENT")


def say(ok: bool, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")))
    return 0 if ok else 1


def atomic(path: pathlib.Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def read_json(path: pathlib.Path, kind: type, default):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (OSError, ValueError):
        return None
    return data if isinstance(data, kind) else None


def region() -> dict:
    r = read_json(REGION, dict, {})
    if r is None:
        raise OSError(f"{REGION.name} is damaged, so it was left as it is")
    return r


def deferred() -> list:
    d = read_json(DEFERRED, list, [])
    return [i for i in (d or []) if i in ITEMS]


def saved_formats() -> str:
    """The formats locale actually set for new sessions, if any."""
    try:
        for line in FORMATS.read_text(encoding="utf-8").splitlines():
            m = re.fullmatch(r"LC_TIME=([a-z]{2,3}_[A-Z]{2})(\.UTF-8)?", line.strip())
            if m:
                return m.group(1)
    except OSError:
        pass
    return ""


def resolve(item: str) -> None:
    left = [i for i in deferred() if i != item]
    if left:
        atomic(DEFERRED, json.dumps(sorted(set(left))) + "\n")
    else:
        DEFERRED.unlink(missing_ok=True)


class locked:
    def __enter__(self):
        GG.mkdir(parents=True, exist_ok=True)
        self.f = open(GG / ".region.lock", "a")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def main(argv: list[str]) -> int:
    cmd, args = (argv[1] if len(argv) > 1 else ""), argv[2:]
    try:
        with locked():
            if cmd == "status" and not args:
                r = region()
                return say(True, region=str(r.get("region") or ""), zone=str(r.get("zone") or ""),
                           formats=saved_formats() or str(r.get("formats") or ""), deferred=deferred())
            if cmd == "set-formats" and len(args) in (1, 2):
                locale = args[0]
                if not re.fullmatch(r"[a-z]{2,3}_[A-Z]{2}", locale):
                    return say(False, error="Those region formats aren't known.")
                name = args[1] if len(args) == 2 else ""
                if len(name) > 60 or any(ord(c) < 32 for c in name):
                    return say(False, error="That isn't a region's name.")
                r = region()
                atomic(FORMATS, "".join(f"{k}={locale}.UTF-8\n" for k in LC))
                r.update(formats=locale, **({"region": name} if name else {}))
                atomic(REGION, json.dumps(r) + "\n")
                resolve("formats")
                return say(True, formats=locale, region=r.get("region", ""))
            if cmd == "set-zone" and len(args) == 1:
                if not re.fullmatch(r"[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}", args[0]):
                    return say(False, error="That time zone isn't known.")
                r = region()
                r["zone"] = args[0]
                atomic(REGION, json.dumps(r) + "\n")
                resolve("timezone")
                return say(True, zone=args[0])
            if cmd == "resolve" and len(args) == 1 and args[0] in ITEMS:
                resolve(args[0])
                return say(True, deferred=deferred())
    except OSError as exc:
        return say(False, error=exc.strerror or str(exc))
    print(__doc__, file=sys.stderr)
    return say(False, error="usage: region.py status | set-formats LOCALE [REGION] | set-zone ZONE | resolve ITEM")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
