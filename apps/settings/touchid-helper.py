#!/usr/bin/env python3
"""Touch ID for sudo and system password prompts (Settings › Touch ID &
Password), as pam_tid does on the Mac: off until chosen.

    touchid-helper.py status    whether it's on: {"admin": true|false, "reader": true|false}
    touchid-helper.py enable    as root (pkexec, org.goldengate.touchid.policy)
    touchid-helper.py disable   as root

On, /etc/pam.d/sudo and /etc/pam.d/polkit-1 ask for a finger first
(`auth sufficient pam_fprintd.so`, one marked line at the top of their auth
section); a finger that doesn't match, or none within the reader's time,
falls through to the password exactly as before. Off removes only that
line. Each file is replaced atomically, keeping its mode, and refused if it
would no longer ask for a password (pam_unix or an include of system-auth).
GG_TOUCHID_ROOT points it at another root (tests)."""
from __future__ import annotations

import json
import os
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(os.environ.get("GG_TOUCHID_ROOT", "/"))
FILES = ["etc/pam.d/sudo", "etc/pam.d/polkit-1"]
MARK = "# CitronOS Touch ID (Settings › Touch ID & Password)"
LINE = f"auth       sufficient   pam_fprintd.so   {MARK}"
MODULES = ["usr/lib/security/pam_fprintd.so", "lib/security/pam_fprintd.so", "usr/lib64/security/pam_fprintd.so"]


def enabled(text: str) -> bool:
    return any(MARK in line for line in text.splitlines())


def without(text: str) -> str:
    return "".join(line for line in text.splitlines(keepends=True) if MARK not in line)


def with_touchid(text: str) -> str:
    lines = without(text).splitlines(keepends=True)
    # Before the first auth line (after the #%PAM-1.0 header and comments).
    at = next((i for i, l in enumerate(lines) if l.split() and l.split()[0] == "auth"), None)
    if at is None:
        at = next((i + 1 for i, l in enumerate(lines) if l.startswith("#%PAM")), 0)
    return "".join(lines[:at]) + LINE + "\n" + "".join(lines[at:])


def still_asks_password(text: str) -> bool:
    body = [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith("#")]
    return any("pam_unix" in l or "system-auth" in l or "system-login" in l or "system-local-login" in l
               or "system-remote-login" in l for l in body if l.split()[0] in ("auth", "-auth", "@include"))


def replace(path: pathlib.Path, text: str) -> None:
    mode = path.stat().st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise


def status() -> dict:
    files = [ROOT / f for f in FILES if (ROOT / f).exists()]
    return {"admin": bool(files) and all(enabled(f.read_text()) for f in files),
            "reader": any((ROOT / m).exists() for m in MODULES)}


def change(on: bool) -> None:
    if on and not any((ROOT / m).exists() for m in MODULES):
        raise SystemExit("fprintd isn't installed (no pam_fprintd.so)")
    planned = []
    for rel in FILES:
        path = ROOT / rel
        if not path.exists():
            continue
        old = path.read_text()
        new = with_touchid(old) if on else without(old)
        if not still_asks_password(new):
            raise SystemExit(f"{path} wouldn't ask for a password any more; left as it is")
        if new != old:
            planned.append((path, new))
    for path, new in planned:
        replace(path, new)


def main(argv: list[str]) -> int:
    if argv == ["status"]:
        print(json.dumps(status()))
        return 0
    if argv in (["enable"], ["disable"]):
        change(argv[0] == "enable")
        print(json.dumps(status()))
        return 0
    raise SystemExit("usage: touchid-helper.py status|enable|disable")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
