#!/usr/bin/env python3
"""Golden Gate Software Update backend: one button checks and installs
everything, the system's Arch packages, Golden Gate itself (from its GitHub
repository, see golden_update.py) and the Flatpak apps from the App Store,
with progress shown in Settings and no terminal.

    check        unprivileged: how many updates there are, and which
    apply        as root (pkexec, see org.goldengate.update.policy): the
                 system packages (pacman -Syu), system-wide Flatpaks, then
                 Golden Gate
    apply-user   unprivileged: the user's own Flatpak apps
    source       unprivileged: where Golden Gate updates come from
    set-source   as root: save {"repo", "branch", "token"} read from stdin
                 (token null keeps the saved one, "" removes it)

Every line on stdout is one JSON event for Settings.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import golden_update  # noqa: E402


def emit(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}, separators=(",", ":")), flush=True)


def run(args: list[str], timeout: int = 90) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout,
                          env={**os.environ, "LC_ALL": "C"})


def pacman_updates() -> tuple[list[str], bool]:
    """(updates, fresh). checkupdates syncs a private copy of the package
    databases under fakeroot (shipped in the image). Without it, an
    unprivileged pacman can't refresh, so report what the last sync knew."""
    tool = shutil.which("checkupdates")
    if tool and shutil.which("fakeroot"):
        proc = run([tool], timeout=120)
        if proc.returncode in (0, 2):        # 2: nothing to update
            return [l.strip() for l in proc.stdout.splitlines() if l.strip()], True
    if not shutil.which("pacman"):
        return [], False
    with tempfile.TemporaryDirectory(prefix="gg-update-") as db:
        os.symlink("/var/lib/pacman/local", os.path.join(db, "local"))
        sync = os.path.join(db, "sync")
        os.mkdir(sync)
        known = "/var/lib/pacman/sync"
        for name in os.listdir(known) if os.path.isdir(known) else []:
            if name.endswith(".db"):
                shutil.copy2(os.path.join(known, name), sync)
        proc = run(["pacman", "-Qu", "--dbpath", db])
        lines = [l.strip() for l in proc.stdout.splitlines() if l.strip()]
        return lines, False


def flatpak_updates(scope: str) -> list[str]:
    if not shutil.which("flatpak"):
        return []
    proc = run(["flatpak", scope, "remote-ls", "--updates", "--columns=application"], timeout=60)
    return [l.strip() for l in proc.stdout.splitlines() if l.strip() and "." in l]


def check() -> int:
    emit("checking", progress=0.08, message="Checking for updates…")
    try:
        system, fresh = pacman_updates()
    except (OSError, subprocess.SubprocessError) as exc:
        emit("error", message=f"Couldn't check for system updates: {exc}")
        return 1
    emit("checking", progress=0.6, message="Checking apps…")
    try:
        apps_system = flatpak_updates("--system")
        apps_user = flatpak_updates("--user")
    except (OSError, subprocess.SubprocessError):
        apps_system, apps_user = [], []
    emit("checking", progress=0.8, message="Checking for Golden Gate updates…")
    try:
        golden = golden_update.check()
    except Exception as exc:                      # never let it hide the other updates
        golden = {"available": False, "error": f"Couldn't check Golden Gate: {exc}"}
    packages = [p.split()[0] + " " + p.split()[-1] if len(p.split()) >= 4 else p for p in system]
    packages += [a + " (app)" for a in apps_system + apps_user]
    if golden.get("available"):
        n = golden.get("ahead") or len(golden.get("notes") or [])
        packages.insert(0, "Golden Gate" + (f" ({n} change{'s' if n != 1 else ''})" if n else ""))
    emit("result", count=len(packages), system=len(system) + (1 if golden.get("available") else 0),
         apps=len(apps_system) + len(apps_user),
         userApps=len(apps_user), packages=packages[:40], stale=not fresh, golden=golden,
         message="" if fresh else "Couldn't reach the update servers; showing what was last known.")
    return 0


TRANSACTION = re.compile(r"\(\s*(\d+)\/(\d+)\)\s+(?:upgrading|installing|reinstalling|removing)\s+(.+)$", re.I)


def stream(cmd: list[str], start: float, span: float, label: str) -> tuple[int, str]:
    """Run cmd, turning pacman/flatpak output into progress events between
    start and start + span."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                            stdin=subprocess.DEVNULL, env={**os.environ, "LC_ALL": "C"})
    assert proc.stdout is not None
    last = ""
    for raw in proc.stdout:
        line = raw.strip()
        if not line:
            continue
        m = TRANSACTION.search(line)
        if m:
            current, total = int(m.group(1)), int(m.group(2))
            emit("progress", progress=start + span * (0.3 + 0.7 * current / max(1, total)),
                 current=current, total=total, remaining=max(0, total - current),
                 message=f"Installing {m.group(3).strip()}")
            continue
        lower = line.lower()
        if "synchronizing package databases" in lower:
            emit("progress", progress=start + span * 0.05, message="Refreshing the software catalog…", remaining=-1)
        elif "resolving dependencies" in lower or "looking for conflicting" in lower:
            emit("progress", progress=start + span * 0.12, message="Resolving dependencies…", remaining=-1)
        elif "retrieving packages" in lower or lower.startswith("downloading"):
            emit("progress", progress=start + span * 0.2, message="Downloading updates…", remaining=-1)
        elif "running post-transaction hooks" in lower:
            emit("progress", progress=start + span * 0.98, message="Finishing installation…", remaining=0)
        elif lower.startswith("updating") or lower.startswith("installing"):
            emit("progress", progress=start + span * 0.5, message=f"{label}: {line[:120]}", remaining=-1)
        if line.startswith("error:") or lower.startswith("error"):
            last = line
    return proc.wait(), last


def apply() -> int:
    if os.geteuid() != 0:
        emit("error", message="Software Update needs administrator authorization.")
        return 77
    emit("progress", progress=0.03, message="Preparing update…", remaining=-1)
    # A previous interrupted run can leave the database locked; only remove the
    # lock when no pacman is running.
    lock = "/var/lib/pacman/db.lck"
    if os.path.exists(lock) and run(["pgrep", "-x", "pacman"]).returncode != 0:
        os.remove(lock)
    code, last = stream(["pacman", "-Syu", "--noconfirm", "--noprogressbar"], 0.03, 0.8, "System")
    if code != 0:
        emit("error", message=last or f"pacman exited with status {code}.")
        return code
    if shutil.which("flatpak"):
        stream(["flatpak", "--system", "update", "-y", "--noninteractive"], 0.8, 0.05, "Apps")
    updated = golden_update.apply(emit)
    emit("done", progress=1.0, completed=datetime.now().isoformat(), restart=updated,
         message="Golden Gate is up to date." + (" Log out and back in to finish." if updated else ""))
    return 0


def apply_user() -> int:
    if not shutil.which("flatpak"):
        emit("done", progress=1.0, message="Golden Gate is up to date.")
        return 0
    emit("progress", progress=0.05, message="Updating apps…", remaining=-1)
    code, last = stream(["flatpak", "--user", "update", "-y", "--noninteractive"], 0.05, 0.9, "Apps")
    if code != 0:
        emit("error", message=last or f"Flatpak exited with status {code}.")
        return code
    emit("done", progress=1.0, message="Golden Gate is up to date.", completed=datetime.now().isoformat())
    return 0


def show_source() -> int:
    src = golden_update.source()
    now = golden_update.installed()
    emit("source", repo=src["repo"], branch=src["branch"], hasToken=bool(src["token"]),
         tokenReadable=os.access(golden_update.path("/etc/golden-gate/update-token"), os.R_OK)
         or not golden_update.path("/etc/golden-gate/update-token").exists(),
         commit=now.get("commit", ""), date=now.get("date", ""), subject=now.get("subject", ""))
    return 0


def set_source() -> int:
    if os.geteuid() != 0:
        emit("error", message="Changing the update source needs administrator authorization.")
        return 77
    try:
        data = json.loads(sys.stdin.readline() or "{}")
        golden_update.set_source(str(data.get("repo", "")).strip(), str(data.get("branch", "")).strip(),
                                 None if data.get("token") is None else str(data["token"]))
    except (ValueError, OSError) as exc:
        emit("error", message=str(exc))
        return 1
    emit("done", message="Saved.")
    return 0


def main() -> int:
    commands = {"check": check, "apply": apply, "apply-user": apply_user,
                "source": show_source, "set-source": set_source}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        print("usage: update-helper.py check|apply|apply-user|source|set-source", file=sys.stderr)
        return 2
    return commands[sys.argv[1]]()


if __name__ == "__main__":
    raise SystemExit(main())
