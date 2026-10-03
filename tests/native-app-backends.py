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

    # App Store: a configured Flatpak remote must produce a usable cached
    # catalog without internet access, and installed state must be reflected.
    fakebin = tmp / "bin"
    fakebin.mkdir()
    flatpak = fakebin / "flatpak"
    flatpak.write_text(
        """#!/bin/sh
args="$*"
case "$args" in
  *"remotes --columns=name"*) printf 'flathub\\n' ;;
  *"list --app --columns=application"*) printf 'org.test.Editor\\n' ;;
  *"remote-ls --updates"*) exit 0 ;;
  *"remote-ls"*"--columns=application,name,description"*)
    printf 'org.test.Editor\\tTest Editor\\tCode editor for development\\n'
    printf 'org.test.Player\\tTest Player\\tMusic and video player\\n'
    ;;
  *) exit 0 ;;
esac
""",
        encoding="utf-8",
    )
    flatpak.chmod(0o755)
    store_env = env.copy()
    store_env["PATH"] = str(fakebin) + os.pathsep + store_env.get("PATH", "")
    code, out = run("apps/software/helper.py", "catalog", env=store_env)
    store = json.loads(out)
    assert code == 0 and store["event"] == "catalog"
    rows = {app["id"]: app for app in store["apps"]}
    assert rows["org.test.Editor"]["installed"] is True
    assert "Development" in rows["org.test.Editor"]["categories"]
    assert "AudioVideo" in rows["org.test.Player"]["categories"]

    # Once a catalog has loaded, a temporary Flathub failure must not throw the
    # storefront back into a connection-error loop. The last good catalog is
    # returned with a warning while the remote recovers.
    flatpak.write_text(
        """#!/bin/sh
case "$*" in
  *"remotes --columns=name"*) printf 'flathub\\n' ;;
  *) printf 'temporary network failure\\n'; exit 1 ;;
esac
""",
        encoding="utf-8",
    )
    flatpak.chmod(0o755)
    code, out = run("apps/software/helper.py", "catalog", env=store_env)
    cached_store = json.loads(out)
    assert code == 0 and cached_store["event"] == "catalog"
    assert {app["id"] for app in cached_store["apps"]} >= {"org.test.Editor", "org.test.Player"}
    assert cached_store["warning"]

    # Software Update: the check path must handle pacman's "no updates"
    # convention and return a structured result without launching a terminal.
    checkupdates = fakebin / "checkupdates"
    checkupdates.write_text("#!/bin/sh\nexit 2\n", encoding="utf-8")
    checkupdates.chmod(0o755)
    # checkupdates refreshes under fakeroot (shipped in the image).
    (fakebin / "fakeroot").write_text("#!/bin/sh\nexec \"$@\"\n", encoding="utf-8")
    (fakebin / "fakeroot").chmod(0o755)
    update_env = env.copy()
    update_env["PATH"] = str(fakebin) + os.pathsep + update_env.get("PATH", "")
    code, out = run("apps/settings/update-helper.py", "check", env=update_env)
    update_lines = [json.loads(line) for line in out.splitlines() if line.strip()]
    assert code == 0
    assert update_lines[-1]["event"] == "result"
    assert update_lines[-1]["count"] == 0

    # Mail with an empty profile must be safely unconfigured and must not
    # attempt network access or require a keyring unlock.
    code, out = run("apps/mail/helper.py", "status", env=env)
    assert code == 0 and json.loads(out)["configured"] is False

# Secrets must live in the keyring, never in JSON config.
mail = (ROOT / "apps/mail/helper.py").read_text(encoding="utf-8")
assert "secret-tool" in mail, "Mail no longer uses the system keyring"
assert '"password": password' not in mail
assert "secret_store(email_addr, password)" in mail

# Messages talks to the iPhone through BlueFerry's bridge: message text and
# recipients go over the bridge's stdin, never into a command line, and
# requests made before the bridge starts are queued, not dropped.
bridge = (ROOT / "apps/messages/Bridge.qml").read_text(encoding="utf-8")
messages_qml = (ROOT / "apps/messages.qml").read_text(encoding="utf-8")
assert "/usr/bin/blueferry-quickshell-bridge" in bridge
assert "stdinEnabled: true" in bridge and "onStarted" in bridge and "queue.push" in bridge
assert "Process {" not in messages_qml, "Messages runs its own processes instead of the bridge"
assert 'bridge.call("send"' in messages_qml and 'bridge.call("send_to_thread"' in messages_qml

print("Native app backends: filesystem, calendar, editor, store, updater and account-state smoke tests passed")
