#!/usr/bin/env python3
"""Opt-in Calendar notifications. Run: reminders.py status|enable|disable|scan.

A systemd --user timer runs scan once per minute, even when Calendar is closed.
Each delivered reminder has a private, crash-safe deduplication record.
"""
from __future__ import annotations

from contextlib import contextmanager
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import helper as calendar

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "systemd/user"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "golden-gate/calendar/reminders-sent.json"
UNIT = "gg-calendar-reminders"
SERVICE = """[Unit]
Description=CitronOS Calendar event notifications
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/share/golden-gate/apps/calendar/reminders.py scan
"""
TIMER = """[Unit]
Description=Check Calendar event notifications every minute
[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true
AccuracySec=1s
Unit=gg-calendar-reminders.service
[Install]
WantedBy=timers.target
"""


def report(ok, **extra):
    print(json.dumps({"ok": ok, **extra}, separators=(",", ":")))
    return 0 if ok else 1


def service(*args):
    try:
        proc = subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(f"User service manager unavailable: {exc}") from exc
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "systemctl failed.")


def configure(action):
    timer = CONFIG / (UNIT + ".timer")
    runner = CONFIG / (UNIT + ".service")
    if action == "status":
        return report(True, enabled=timer.is_file() and runner.is_file())
    if action == "enable":
        created = []
        try:
            CONFIG.mkdir(parents=True, exist_ok=True)
            for path, content in ((runner, SERVICE), (timer, TIMER)):
                if path.exists():
                    if path.read_text(encoding="utf-8") != content:
                        raise RuntimeError(f"{path.name} already exists with different contents.")
                    continue
                fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                created.append(path)
                with os.fdopen(fd, "w", encoding="utf-8") as out:
                    out.write(content)
            service("daemon-reload")
            service("enable", "--now", UNIT + ".timer")
        except (OSError, RuntimeError) as exc:
            for path in created:
                path.unlink(missing_ok=True)
            try:
                service("disable", "--now", UNIT + ".timer")
                service("daemon-reload")
            except RuntimeError:
                pass
            return report(False, error=f"Could not enable Calendar reminders: {exc}")
        return report(True, enabled=True)
    if action == "disable":
        try:
            service("disable", "--now", UNIT + ".timer")
            timer.unlink(missing_ok=True)
            runner.unlink(missing_ok=True)
            service("daemon-reload")
        except (OSError, RuntimeError) as exc:
            return report(False, error=f"Could not turn off Calendar reminders: {exc}")
        return report(True, enabled=False)
    return report(False, error="Choose status, enable, disable, or scan.")


def instances_on(events, day):
    key = day.isoformat()
    for event in events:
        if calendar.check(event):
            continue
        exceptions = event.get("exceptions") or {}
        if calendar.occurs_on(event, day) and key not in exceptions:
            yield event, key, event
        for original, override in exceptions.items():
            if isinstance(override, dict) and override.get("date") == key:
                yield event, original, {**event, **override}


def due_notifications(events, now=None):
    """Yield (unique-key, title, body) only within 2 minutes after due."""
    now = now or dt.datetime.now()
    for day_delta in (-1, 0, 1):
        date = now.date() + dt.timedelta(days=day_delta)
        for series, original, instance in instances_on(events, date):
            minutes = instance.get("reminder", series.get("reminder", -1))
            if minutes not in (0, 5, 15, 60):
                continue
            try:
                hour, minute = map(int, (instance.get("time") or "09:00").split(":"))
                start = dt.datetime.combine(date, dt.time(hour, minute))
            except (TypeError, ValueError):
                continue
            due = start - dt.timedelta(minutes=minutes)
            if not 0 <= (now - due).total_seconds() < 120:
                continue
            identity = f"{series['id']}|{original}|{start.isoformat()}|{minutes}"
            key = hashlib.sha256(identity.encode("utf-8")).hexdigest()
            lead = "Starting now" if minutes == 0 else f"In {minutes} minutes"
            yield key, instance["title"], f"{lead} · {instance.get('time') or 'All day'}"


@contextmanager
def locked_history():
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE.with_name(".reminders.lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def read_history():
    try:
        data = json.loads(STATE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict) or not all(
            isinstance(k, str) and type(v) in (int, float) for k, v in data.items()):
        raise ValueError("Reminder history is damaged; delivery has stopped to prevent duplicates.")
    return data


def save_history(data):
    fd, temp = tempfile.mkstemp(dir=STATE.parent, prefix=".reminders-")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, separators=(",", ":"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, STATE)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def scan():
    try:
        with calendar.locked():
            events = calendar.load()
        now = dt.datetime.now()
        due = list(due_notifications(events, now))
        with locked_history():
            sent = read_history()
            cutoff = now.timestamp() - 35 * 86400
            sent = {k: stamp for k, stamp in sent.items() if stamp >= cutoff}
            count = 0
            for key, title, body in due:
                if key in sent:
                    continue
                try:
                    p = subprocess.run(["notify-send", "-a", "Calendar",
                                        "-i", "x-office-calendar", "--", title, body],
                                       capture_output=True, text=True, timeout=10)
                except (OSError, subprocess.SubprocessError) as exc:
                    raise RuntimeError(f"Desktop notification failed: {exc}") from exc
                if p.returncode:
                    raise RuntimeError(p.stderr.strip() or "The desktop rejected the notification.")
                sent[key] = now.timestamp()
                count += 1
                save_history(sent)
            save_history(sent)
        return report(True, delivered=count)
    except (OSError, ValueError, RuntimeError, calendar.Broken) as exc:
        return report(False, error=str(exc))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(report(False, error="Choose status, enable, disable, or scan."))
    raise SystemExit(scan() if sys.argv[1] == "scan" else configure(sys.argv[1]))
