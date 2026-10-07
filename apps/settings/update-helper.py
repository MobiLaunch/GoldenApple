#!/usr/bin/env python3
"""CitronOS Software Update backend: one button checks and installs
everything, the system's Arch packages, CitronOS itself (from its GitHub
repository, see golden_update.py) and the Flatpak apps from the App Store,
with progress shown in Settings and no terminal.

    check        unprivileged: how many updates there are, and which
    apply        as root (pkexec, see org.goldengate.update.policy): the
                 system packages (pacman -Syu), system-wide Flatpaks, then
                 CitronOS
    apply-user   unprivileged: the user's own Flatpak apps
    source       unprivileged: where CitronOS updates come from
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
    emit("checking", progress=0.8, message="Checking for CitronOS updates…")
    try:
        golden = golden_update.check()
    except Exception as exc:                      # never let it hide the other updates
        golden = {"available": False, "error": f"Couldn't check CitronOS: {exc}"}
    packages = [p.split()[0] + " " + p.split()[-1] if len(p.split()) >= 4 else p for p in system]
    packages += [a + " (app)" for a in apps_system + apps_user]
    if golden.get("available"):
        n = golden.get("ahead") or len(golden.get("notes") or [])
        packages.insert(0, "CitronOS" + (f" ({n} change{'s' if n != 1 else ''})" if n else ""))
    emit("result", count=len(packages), system=len(system) + (1 if golden.get("available") else 0),
         apps=len(apps_system) + len(apps_user),
         userApps=len(apps_user), packages=packages[:40], stale=not fresh, golden=golden,
         message="" if fresh else "Couldn't reach the update servers; showing what was last known.")
    return 0


TRANSACTION = re.compile(r"\(\s*(\d+)\/(\d+)\)\s+(?:upgrading|installing|reinstalling|removing)\s+(.+)$", re.I)


def stream(cmd: list[str], start: float, span: float, label: str) -> tuple[int, str]:
    """Run cmd, turning pacman/flatpak output into progress events between
    start and start + span. Returns its status and its error lines."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                            stdin=subprocess.DEVNULL, env={**os.environ, "LC_ALL": "C"})
    assert proc.stdout is not None
    errors: list[str] = []
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
        if lower.startswith("error"):
            errors.append(line)
    return proc.wait(), "\n".join(errors[-20:])


# pacman couldn't verify a package or a database: the keyring is missing,
# out of date or damaged.
SIGNATURE = re.compile(r"signature|unknown trust|pgp|gpgme|keyring|corrupted package|could not be looked up|"
                       r"invalid key|key .* (?:disabled|expired)|marginal trust", re.I)


def system_upgrade() -> tuple[int, str]:
    return stream(["pacman", "-Syu", "--noconfirm", "--noprogressbar"], 0.03, 0.8, "System")


def repair_keyring(initial: bool) -> None:
    """Bring pacman's keyring up to date: create it if it's missing; on a
    repair, rebuild it from the installed keyring package and fetch the
    current packager keys. Then install the newest archlinux-keyring, which
    carries the keys that sign today's packages."""
    golden_update.ensure_keyring(golden_update.ROOT)
    if not initial:
        run(["pacman-key", "--init"], timeout=300)
        run(["pacman-key", "--populate"], timeout=300)
        if shutil.which("archlinux-keyring-wkd-sync"):
            emit("progress", progress=0.12, message="Fetching the current package signing keys…", remaining=-1)
            try:
                run(["archlinux-keyring-wkd-sync"], timeout=600)
            except subprocess.TimeoutExpired:
                pass
    emit("progress", progress=0.05 if initial else 0.15, message="Updating the package signing keys…", remaining=-1)
    try:
        run(["pacman", "-Sy", "--noconfirm", "--needed", "--noprogressbar", "archlinux-keyring"], timeout=600)
    except subprocess.TimeoutExpired:
        pass


def explain_pacman(errors: str) -> str:
    """The error to show for a failed system update: what went wrong, in words
    that say what to do, with pacman's own line after it."""
    last = errors.strip().splitlines()[-1] if errors.strip() else ""
    if not last:
        return ""
    if SIGNATURE.search(errors):
        hint = ("Packages couldn't be verified because the package signing keys are out of date. "
                "In Terminal, run: sudo pacman-key --populate && sudo pacman -Sy archlinux-keyring, "
                "then try again.")
    elif "could not resolve host" in errors.lower() or "failed retrieving file" in errors.lower():
        hint = "Couldn't download the updates. Check the internet connection and try again."
    elif "conflicting files" in errors.lower() or "exists in filesystem" in errors.lower():
        hint = "An update would overwrite files that another package owns."
    elif "not enough free disk space" in errors.lower():
        hint = "There isn't enough free disk space for the updates."
    elif "unable to lock database" in errors.lower():
        hint = "Another app is installing software right now. Try again when it finishes."
    else:
        return last
    return f"{hint} ({last})"


def apply() -> int:
    if os.geteuid() != 0:
        emit("error", message="Software Update needs administrator authorization.")
        return 77
    emit("progress", progress=0.03, message="Preparing update…", remaining=-1)
    # A previous interrupted run can leave the database locked; only remove the
    # lock when no pacman is running.
    lock = "/var/lib/pacman/db.lck"
    if os.path.exists(lock):
        if run(["pgrep", "-x", "pacman"]).returncode == 0:
            emit("error", message="Another app is installing software right now. Try again when it finishes.")
            return 1
        os.remove(lock)
    # Packages are signed by keys newer than the ones the computer was
    # installed with, so bring the keyring up to date first (as Arch advises),
    # and repair it once if pacman still can't verify a package.
    repair_keyring(initial=True)
    code, errors = system_upgrade()
    if code != 0 and SIGNATURE.search(errors):
        emit("progress", progress=0.1, message="Repairing the package signing keys…", remaining=-1)
        repair_keyring(initial=False)
        code, errors = system_upgrade()
    # Each part says how it went; the last event is "done" only if none
    # failed. A part that failed stays failed (and its update available).
    parts: list[dict] = []
    parts.append({"name": "System packages", "ok": code == 0,
                  "detail": (explain_pacman(errors) or f"pacman exited with status {code}.") if code != 0 else ""})
    if shutil.which("flatpak"):
        fcode, ferrors = stream(["flatpak", "--system", "update", "-y", "--noninteractive"], 0.8, 0.05, "Apps")
        parts.append({"name": "Apps for everyone", "ok": fcode == 0,
                      "detail": ((ferrors.splitlines() or [""])[-1] or f"Flatpak exited with status {fcode}.") if fcode else ""})
    # CitronOS still updates when the system packages couldn't: its fixes
    # (including ones for updating itself) shouldn't wait on them. Its own
    # errors are its part's result, not the end of the whole update.
    problems: list[str] = []

    def golden_emit(event: str, **payload: object) -> None:
        if event == "error":
            problems.append(str(payload.get("message") or "CitronOS couldn't be updated."))
        else:
            emit(event, **payload)

    outcome = golden_update.apply(golden_emit)
    parts.append({"name": "CitronOS", "ok": outcome != "failed",
                  "detail": problems[-1] if problems else ("" if outcome != "failed" else "CitronOS couldn't be updated.")})
    updated = outcome == "updated"
    failed = [p for p in parts if not p["ok"]]
    if failed:
        message = " ".join(f"{p['name']}: {p['detail']}" for p in failed)
        if len(failed) < len(parts):
            done = [p["name"] for p in parts if p["ok"]]
            message = "Some updates didn't install. " + message + " (" + ", ".join(done) + " updated.)"
        emit("error", message=message, parts=parts, restart=updated)
        return 1
    emit("done", progress=1.0, completed=datetime.now().isoformat(), restart=updated, parts=parts,
         message="CitronOS is up to date." + (" Log out and back in to finish." if updated else ""))
    return 0


def apply_user() -> int:
    if not shutil.which("flatpak"):
        emit("done", progress=1.0, message="CitronOS is up to date.")
        return 0
    emit("progress", progress=0.05, message="Updating apps…", remaining=-1)
    code, errors = stream(["flatpak", "--user", "update", "-y", "--noninteractive"], 0.05, 0.9, "Apps")
    if code != 0:
        emit("error", message=(errors.splitlines() or [""])[-1] or f"Flatpak exited with status {code}.")
        return code
    emit("done", progress=1.0, message="CitronOS is up to date.", completed=datetime.now().isoformat())
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
        repo, branch = str(data.get("repo", "")).strip(), str(data.get("branch", "")).strip()
        token = None if data.get("token") is None else golden_update.clean_token(str(data["token"]))
        # Ask GitHub first, so a token it won't take is refused here, with the
        # reason, instead of being saved and failing quietly later. Without a
        # connection it's saved anyway.
        problem = golden_update.verify_source(repo, branch, golden_update.source()["token"] if token is None else token)
        if problem and problem[1]:
            emit("error", message=problem[0])
            return 1
        golden_update.set_source(repo, branch, token)
    except (ValueError, OSError) as exc:
        emit("error", message=str(exc))
        return 1
    emit("done", message="Saved." if not problem else "Saved, but " + problem[0][0].lower() + problem[0][1:])
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
