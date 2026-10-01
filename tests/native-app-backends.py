#!/usr/bin/env python3
"""Functional smoke tests for Golden Gate native app backends.

These run without Quickshell, network access, or touching the real user profile.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable


def run(helper: str, *args: str, env: dict[str, str], stdin: str = "") -> tuple[int, str]:
    p = subprocess.run(
        [PY, str(ROOT / helper), *args],
        input=stdin,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    return p.returncode, p.stdout.strip()


with tempfile.TemporaryDirectory() as raw:
    tmp = Path(raw)
    home = tmp / "home"
    home.mkdir()
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(tmp / "config")
    env["XDG_DATA_HOME"] = str(tmp / "data")

    # Calendar: persistent add/list/delete round-trip.
    code, out = run("apps/calendar/helper.py", "list", env=env)
    assert code == 0 and json.loads(out)["events"] == []

    event = {"title": "Hardware test", "date": "2026-10-02", "time": "14:30", "calendar": "Work"}
    code, out = run("apps/calendar/helper.py", "add", env=env, stdin=json.dumps(event))
    added = json.loads(out)
    assert code == 0 and added["ok"] and added["event"]["title"] == event["title"]
    event_id = added["event"]["id"]

    code, out = run("apps/calendar/helper.py", "list", env=env)
    listed = json.loads(out)
    assert code == 0 and len(listed["events"]) == 1

    code, out = run("apps/calendar/helper.py", "delete", event_id, env=env)
    assert code == 0 and json.loads(out)["ok"]

    # TextEdit: real atomic file write/read.
    doc = tmp / "Documents" / "hello.txt"
    body = "Golden Gate\nshared controls\n"
    code, out = run("apps/textedit/helper.py", "write", str(doc), env=env, stdin=body)
    assert code == 0 and json.loads(out)["ok"] and doc.read_text() == body
    code, out = run("apps/textedit/helper.py", "read", str(doc), env=env)
    assert code == 0 and json.loads(out)["text"] == body

    # Files: list/mkdir/rename on a temporary real filesystem.
    folder = tmp / "files"
    folder.mkdir()
    (folder / "alpha.txt").write_text("a", encoding="utf-8")
    code, out = run("apps/files/helper.py", "list", str(folder), env=env)
    listing = json.loads(out)
    assert code == 0 and listing["ok"] and listing["entries"][0]["name"] == "alpha.txt"

    code, out = run("apps/files/helper.py", "mkdir", str(folder), "New Folder", env=env)
    made = json.loads(out)
    assert code == 0 and made["ok"] and (folder / "New Folder").is_dir()

    code, out = run("apps/files/helper.py", "rename", str(folder / "alpha.txt"), "beta.txt", env=env)
    renamed = json.loads(out)
    assert code == 0 and renamed["ok"] and (folder / "beta.txt").is_file()

    # Mail/Messages with an empty profile must be safely unconfigured and must
    # not attempt network access or require a keyring unlock.
    code, out = run("apps/mail/helper.py", "status", env=env)
    assert code == 0 and json.loads(out)["configured"] is False
    code, out = run("apps/messages/helper.py", "status", env=env)
    assert code == 0 and json.loads(out)["configured"] is False

# Secrets must live in the keyring, never in JSON config.
mail = (ROOT / "apps/mail/helper.py").read_text(encoding="utf-8")
messages = (ROOT / "apps/messages/helper.py").read_text(encoding="utf-8")
for name, source in [("Mail", mail), ("Messages", messages)]:
    assert "secret-tool" in source, f"{name} no longer uses the system keyring"
assert '"password": password' not in mail
assert '"access_token": token' not in messages
assert "secret_store(email_addr, password)" in mail
assert "secret_store(user_id, token)" in messages

print("Native app backends: filesystem, calendar, editor and account-state smoke tests passed")
