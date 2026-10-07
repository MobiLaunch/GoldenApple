#!/usr/bin/env python3
"""Clock's alarms and timer, kept by the user's systemd so they go off with
Clock closed, after a restart (alarms) and after sleep.

    helper.py status                     {"alarms": [...], "timer": {...}}
    helper.py alarm-add HH:MM NAME [daily]
    helper.py alarm-remove ID
    helper.py timer-start SECONDS        a countdown; its deadline is kept on disk
    helper.py timer-pause | timer-cancel
    helper.py fire ID | fire-timer       run by systemd when one is due

An alarm is a pair of unit files in ~/.config/systemd/user (gg-alarm-ID.timer
and .service, Persistent=true so one missed while the computer was off goes
off at the next login) and an entry in ~/.local/share/golden-gate/clock.json.
The timer is a transient unit (gg-clock-timer) set for a wall-clock time, so
time asleep counts. Every change is reported only once systemd took it:
{"ok": true, …} or {"ok": false, "error": …}."""
from __future__ import annotations

import datetime
import fcntl
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import uuid

HELPER = os.path.realpath(__file__)


def data_file() -> pathlib.Path:
    base = pathlib.Path(os.environ.get("XDG_DATA_HOME") or pathlib.Path.home() / ".local/share")
    return base / "golden-gate/clock.json"


def units_dir() -> pathlib.Path:
    base = pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")
    return base / "systemd/user"


def say(ok: bool, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")))
    return 0 if ok else 1


class Failed(Exception):
    pass


def systemctl(*args: str) -> None:
    try:
        p = subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        raise Failed(f"The user service manager isn't available ({exc}).")
    if p.returncode != 0:
        raise Failed((p.stderr.strip().splitlines() or [f"systemctl exited with status {p.returncode}"])[-1])


def load() -> dict:
    try:
        data = json.loads(data_file().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as exc:
        raise Failed(f"Clock's saved alarms can't be read ({exc}).")


def save(data: dict) -> None:
    f = data_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=f.parent, prefix=".clock.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        json.dump(data, out, indent=1)
        out.flush()
        os.fsync(out.fileno())
    os.replace(tmp, f)


class locked:
    def __enter__(self):
        data_file().parent.mkdir(parents=True, exist_ok=True)
        self.f = open(data_file().parent / ".clock.lock", "a")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def next_time(hhmm: str, now: datetime.datetime) -> datetime.datetime:
    h, m = map(int, hhmm.split(":"))
    when = now.replace(hour=h, minute=m, second=0, microsecond=0)
    return when if when > now else when + datetime.timedelta(days=1)


def alarm_add(hhmm: str, name: str, daily: bool) -> int:
    if not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", hhmm):
        return say(False, error="Enter a time as HH:MM, such as 07:30.")
    name = " ".join(name.split())[:80] or "Alarm"
    aid = uuid.uuid4().hex[:12]
    when = next_time(hhmm, datetime.datetime.now())
    calendar = f"*-*-* {hhmm}:00" if daily else when.strftime("%Y-%m-%d %H:%M:00")
    unit = f"gg-alarm-{aid}"
    d = units_dir()
    try:
        with locked():
            data = load()
            d.mkdir(parents=True, exist_ok=True)
            (d / f"{unit}.service").write_text(
                f"[Unit]\nDescription=Clock alarm\n\n[Service]\nType=oneshot\n"
                f"ExecStart=/usr/bin/python3 {HELPER} fire {aid}\n")
            (d / f"{unit}.timer").write_text(
                f"[Unit]\nDescription=Clock alarm at {hhmm}\n\n[Timer]\nOnCalendar={calendar}\n"
                f"Persistent=true\nAccuracySec=1s\n\n[Install]\nWantedBy=timers.target\n")
            try:
                systemctl("daemon-reload")
                systemctl("enable", "--now", f"{unit}.timer")
            except Failed:
                for ext in ("service", "timer"):
                    (d / f"{unit}.{ext}").unlink(missing_ok=True)
                raise
            alarm = {"id": aid, "time": hhmm, "name": name, "daily": daily, "next": when.isoformat(timespec="minutes")}
            data.setdefault("alarms", []).append(alarm)
            save(data)
    except Failed as exc:
        return say(False, error=f"The alarm wasn't set: {exc}")
    return say(True, alarm=alarm)


def remove_units(aid: str) -> None:
    unit = f"gg-alarm-{aid}"
    try:
        systemctl("disable", "--now", f"{unit}.timer")
    except Failed:
        pass                                    # already gone: the files go anyway
    for ext in ("service", "timer"):
        (units_dir() / f"{unit}.{ext}").unlink(missing_ok=True)
    try:
        systemctl("daemon-reload")
    except Failed:
        pass


def alarm_remove(aid: str) -> int:
    try:
        with locked():
            data = load()
            alarms = data.get("alarms", [])
            if not any(a.get("id") == aid for a in alarms):
                return say(False, error="That alarm no longer exists.")
            remove_units(aid)
            data["alarms"] = [a for a in alarms if a.get("id") != aid]
            save(data)
    except Failed as exc:
        return say(False, error=str(exc))
    return say(True)


def notify(title: str, body: str) -> None:
    try:
        subprocess.run(["notify-send", "-u", "critical", "-a", "Clock", "-i", "alarm-symbolic", title, body], timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass


def fire(aid: str) -> int:
    with locked():
        data = load()
        alarm = next((a for a in data.get("alarms", []) if a.get("id") == aid), None)
        if alarm is None:
            remove_units(aid)
            return 0
        notify("Alarm", f"{alarm['name']} · {alarm['time']}")
        if alarm.get("daily"):
            alarm["next"] = next_time(alarm["time"], datetime.datetime.now()).isoformat(timespec="minutes")
        else:
            remove_units(aid)
            data["alarms"] = [a for a in data["alarms"] if a.get("id") != aid]
        save(data)
    return 0


TIMER_UNIT = "gg-clock-timer"


def timer_state(data: dict) -> dict:
    t = data.get("timer") or {}
    if t.get("deadline") and t["deadline"] <= time.time():
        t = {"seconds": t.get("seconds", 0), "finished": t["deadline"]}
    return t


def timer_start(seconds: str) -> int:
    try:
        s = int(seconds)
    except ValueError:
        s = 0
    if not 1 <= s <= 24 * 3600 * 7:
        return say(False, error="Choose a length for the timer.")
    try:
        with locked():
            data = load()
            prior = data.get("timer") or {}
            total = prior.get("seconds") or s
            deadline = time.time() + s
            stop_timer()
            when = datetime.datetime.fromtimestamp(deadline).strftime("%Y-%m-%d %H:%M:%S")
            try:
                p = subprocess.run(["systemd-run", "--user", "--quiet", f"--unit={TIMER_UNIT}",
                                    f"--on-calendar={when}", "--timer-property=AccuracySec=1s",
                                    "/usr/bin/python3", HELPER, "fire-timer"],
                                   capture_output=True, text=True, timeout=20)
            except (OSError, subprocess.SubprocessError) as exc:
                raise Failed(f"The user service manager isn't available ({exc}).")
            if p.returncode != 0:
                raise Failed((p.stderr.strip().splitlines() or [f"systemd-run exited with status {p.returncode}"])[-1])
            data["timer"] = {"seconds": total if prior.get("remaining") else s, "deadline": deadline}
            save(data)
    except Failed as exc:
        return say(False, error=f"The timer didn't start: {exc}")
    return say(True, timer=data["timer"])


def stop_timer() -> None:
    for args in (("stop", f"{TIMER_UNIT}.timer"), ("reset-failed", f"{TIMER_UNIT}.timer", f"{TIMER_UNIT}.service")):
        try:
            systemctl(*args)
        except Failed:
            pass


def timer_pause() -> int:
    with locked():
        data = load()
        t = data.get("timer") or {}
        if not t.get("deadline"):
            return say(False, error="The timer isn't running.")
        stop_timer()
        data["timer"] = {"seconds": t.get("seconds", 0), "remaining": max(0, round(t["deadline"] - time.time()))}
        save(data)
    return say(True, timer=data["timer"])


def timer_cancel() -> int:
    with locked():
        data = load()
        stop_timer()
        data.pop("timer", None)
        save(data)
    return say(True)


def fire_timer() -> int:
    with locked():
        data = load()
        t = data.get("timer") or {}
        notify("Timer", "Your timer has finished.")
        data["timer"] = {"seconds": t.get("seconds", 0), "finished": time.time()}
        save(data)
    return 0


def status() -> int:
    try:
        data = load()
    except Failed as exc:
        return say(False, error=str(exc))
    return say(True, alarms=sorted(data.get("alarms", []), key=lambda a: a.get("time", "")),
               timer=timer_state(data), now=time.time())


def main(argv: list[str]) -> int:
    cmd, args = (argv[1] if len(argv) > 1 else ""), argv[2:]
    if cmd == "status":
        return status()
    if cmd == "alarm-add" and len(args) in (2, 3):
        return alarm_add(args[0], args[1], len(args) == 3 and args[2] == "daily")
    if cmd == "alarm-remove" and len(args) == 1:
        return alarm_remove(args[0])
    if cmd == "timer-start" and len(args) == 1:
        return timer_start(args[0])
    if cmd == "timer-pause":
        return timer_pause()
    if cmd == "timer-cancel":
        return timer_cancel()
    if cmd == "fire" and len(args) == 1:
        return fire(args[0])
    if cmd == "fire-timer":
        return fire_timer()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
