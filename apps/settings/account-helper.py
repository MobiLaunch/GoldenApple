#!/usr/bin/env python3
"""Privileged account actions used by Golden Gate Settings.

The helper is intentionally tiny: Polkit authenticates the caller, PKEXEC_UID
identifies whose password may be changed, and the new password is accepted only
over stdin. It is never placed in argv, a temporary file, or a log.
"""
from __future__ import annotations

import json
import os
import pwd
import subprocess
import sys


def emit(ok: bool, message: str) -> None:
    print(json.dumps({"ok": ok, "message": message}, separators=(",", ":")), flush=True)


def caller_name() -> str:
    raw_uid = os.environ.get("PKEXEC_UID") or os.environ.get("SUDO_UID")
    if not raw_uid:
        raise RuntimeError("The requesting account could not be identified.")
    try:
        uid = int(raw_uid)
        record = pwd.getpwuid(uid)
    except (ValueError, KeyError):
        raise RuntimeError("The requesting account could not be identified.")
    if uid < 1000 or uid >= 60000:
        raise RuntimeError("Only a normal local user password can be changed here.")
    return record.pw_name


def change_password() -> int:
    if os.geteuid() != 0:
        emit(False, "Administrator authorization is required.")
        return 77

    try:
        username = caller_name()
        payload = json.load(sys.stdin)
        password = str(payload.get("password") or "")
    except (RuntimeError, json.JSONDecodeError) as exc:
        emit(False, str(exc))
        return 2

    if len(password) < 6:
        emit(False, "Use at least 6 characters for the new password.")
        return 2
    if "\n" in password or "\r" in password or ":" in password:
        emit(False, "The password contains a character that cannot be used here.")
        return 2

    proc = subprocess.run(
        ["chpasswd"],
        input=f"{username}:{password}\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if proc.returncode != 0:
        emit(False, "The password could not be changed.")
        return proc.returncode or 1

    emit(True, "Password changed.")
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "password":
        return change_password()
    print("usage: account-helper.py password", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
