#!/usr/bin/env python3
"""Clock's alarms and timer, kept by the user's systemd so they go off with
Clock closed, after a restart (alarms) and after sleep.

    helper.py status                     {"alarms": [...], "timer": {...}}
    helper.py alarm-add HH:MM NAME [daily]
    helper.py alarm-remove ID
    helper.py timer-start SECONDS        a countdown; its deadline is kept on disk
    helper.py timer-pause | timer-cancel
    helper.py fire ID | fire-timer GEN   run by systemd when one is due

An alarm is a pair of unit files in ~/.config/systemd/user (gg-alarm-ID.timer
and .service, Persistent=true so one missed while the computer was off goes
off at the next login) and an entry in ~/.local/share/golden-gate/clock.json.
The timer is a transient unit (gg-clock-timer-GEN) set for a wall-clock time,
so time asleep counts; every start has a new GEN, and a firing whose GEN isn't
the running timer's (cancelled, paused, restarted) does nothing.

Every change is reported only once systemd took it and it's saved: a unit
that was turned on is turned off again if saving fails, and an alarm is
forgotten only once its unit is off. Each command prints {"ok": true, …} or
{"ok": false, "error": …}; "note" says when something was done but a leftover
unit couldn't be stopped (it won't go off: its GEN is no longer the timer's)."""
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
            try:
                save(data)
            except OSError as exc:
                # Not kept, so not left on: an alarm Clock doesn't list can't be deleted.
                remove_units(aid, quiet=True)
                raise Failed(f"it couldn't be saved ({exc.strerror or exc})")
    except Failed as exc:
        return say(False, error=f"The alarm wasn't set: {exc}")
    except OSError as exc:
        return say(False, error=f"The alarm wasn't set: {exc.strerror or exc}")
    return say(True, alarm=alarm)


GONE = ("not loaded", "does not exist", "not found", "no such file")


def gone(exc: Failed) -> bool:
    """systemd refused because there's nothing to stop: that's done, not failed."""
    return any(g in str(exc).lower() for g in GONE)


def remove_units(aid: str, quiet: bool = False) -> None:
    """Turns an alarm's unit off and removes its files. Raises Failed if it
    may still be on (unless quiet: then it's as off as it can be made)."""
    unit = f"gg-alarm-{aid}"
    try:
        systemctl("disable", "--now", f"{unit}.timer")
    except Failed as exc:
        if not (quiet or gone(exc)):
            raise
    for ext in ("service", "timer"):
        (units_dir() / f"{unit}.{ext}").unlink(missing_ok=True)
    try:
        systemctl("daemon-reload")
    except Failed:
        pass                                    # the files are gone; it's off already


def alarm_remove(aid: str) -> int:
    try:
        with locked():
            data = load()
            alarms = data.get("alarms", [])
            if not any(a.get("id") == aid for a in alarms):
                return say(False, error="That alarm no longer exists.")
            # Off first: an alarm is forgotten only once it can't go off.
            remove_units(aid)
            data["alarms"] = [a for a in alarms if a.get("id") != aid]
            save(data)
    except Failed as exc:
        return say(False, error=f"The alarm wasn't deleted: {exc}")
    except OSError as exc:
        # Its unit is off but the list couldn't be saved: a firing finds the
        # unit gone and an alarm that no longer has one says nothing (fire).
        return say(False, error=f"The alarm is off, but Clock's list couldn't be saved ({exc.strerror or exc}).")
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
            remove_units(aid, quiet=True)       # a leftover: it says nothing
            return 0
        notify("Alarm", f"{alarm['name']} · {alarm['time']}")
        if alarm.get("daily"):
            alarm["next"] = next_time(alarm["time"], datetime.datetime.now()).isoformat(timespec="minutes")
        else:
            remove_units(aid, quiet=True)
            data["alarms"] = [a for a in data["alarms"] if a.get("id") != aid]
        save(data)
    return 0


TIMER_UNIT = "gg-clock-timer"


def timer_unit(gen: str) -> str:
    return f"{TIMER_UNIT}-{gen}" if gen else TIMER_UNIT


def timer_state(data: dict) -> dict:
    t = data.get("timer") or {}
    if t.get("deadline") and t["deadline"] <= time.time():
        t = {"seconds": t.get("seconds", 0), "finished": t["deadline"]}
    return t


def arm(gen: str, deadline: float) -> None:
    when = datetime.datetime.fromtimestamp(deadline).strftime("%Y-%m-%d %H:%M:%S")
    try:
        p = subprocess.run(["systemd-run", "--user", "--quiet", f"--unit={timer_unit(gen)}",
                            f"--on-calendar={when}", "--timer-property=AccuracySec=1s",
                            "/usr/bin/python3", HELPER, "fire-timer", gen],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        raise Failed(f"The user service manager isn't available ({exc}).")
    if p.returncode != 0:
        raise Failed((p.stderr.strip().splitlines() or [f"systemd-run exited with status {p.returncode}"])[-1])


def stop_timer(gen: str) -> str:
    """Stops a timer's unit; "" once it's off (or was never there), else why not."""
    try:
        systemctl("stop", f"{timer_unit(gen)}.timer")
    except Failed as exc:
        if not gone(exc):
            return str(exc)
    try:
        systemctl("reset-failed", f"{timer_unit(gen)}.timer", f"{timer_unit(gen)}.service")
    except Failed:
        pass                                    # nothing failed to reset
    return ""


def leftover(why: str) -> dict:
    return {"note": f"Its alert was turned off, but systemd couldn't remove it ({why}); it won't go off."} if why else {}


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
            gen = uuid.uuid4().hex[:12]
            deadline = time.time() + s
            # The new one is on before the old one goes: if anything fails, the
            # timer that was running still is.
            arm(gen, deadline)
            data["timer"] = {"seconds": (prior.get("seconds") or s) if prior.get("remaining") else s,
                             "deadline": deadline, "gen": gen}
            try:
                save(data)
            except OSError as exc:
                stop_timer(gen)
                raise Failed(f"it couldn't be saved ({exc.strerror or exc})")
            why = stop_timer(prior.get("gen", "")) if prior.get("deadline") else ""
    except Failed as exc:
        return say(False, error=f"The timer didn't start: {exc}")
    return say(True, timer=data["timer"], **leftover(why))


def timer_pause() -> int:
    try:
        with locked():
            data = load()
            t = data.get("timer") or {}
            if not t.get("deadline"):
                return say(False, error="The timer isn't running.")
            data["timer"] = {"seconds": t.get("seconds", 0), "remaining": max(0, round(t["deadline"] - time.time()))}
            save(data)                          # paused on disk first: its unit's firing is now a leftover
            why = stop_timer(t.get("gen", ""))
    except Failed as exc:
        return say(False, error=str(exc))
    except OSError as exc:
        return say(False, error=f"The timer wasn't paused: it couldn't be saved ({exc.strerror or exc}).")
    return say(True, timer=data["timer"], **leftover(why))


def timer_cancel() -> int:
    try:
        with locked():
            data = load()
            t = data.pop("timer", None) or {}
            save(data)                          # cancelled on disk first, as for pause
            why = stop_timer(t.get("gen", "")) if t.get("deadline") else ""
    except Failed as exc:
        return say(False, error=str(exc))
    except OSError as exc:
        return say(False, error=f"The timer wasn't cancelled: it couldn't be saved ({exc.strerror or exc}).")
    return say(True, **leftover(why))


def fire_timer(gen: str) -> int:
    with locked():
        data = load()
        t = data.get("timer") or {}
        # Only the running timer's own unit, once it's due: a cancelled,
        # paused or restarted one's firing is a leftover and says nothing.
        if not t.get("deadline") or t.get("gen", "") != gen or t["deadline"] > time.time() + 5:
            return 0
        notify("Timer", "Your timer has finished.")
        data["timer"] = {"seconds": t.get("seconds", 0), "finished": time.time()}
        save(data)
    return 0


def reconcile(data: dict) -> str:
    """A running timer whose unit isn't there (the user's service manager was
    restarted, which drops transient units) is set again. "" if all's well."""
    t = data.get("timer") or {}
    if not t.get("deadline") or t["deadline"] <= time.time():
        return ""
    try:
        p = subprocess.run(["systemctl", "--user", "is-active", f"{timer_unit(t.get('gen', ''))}.timer"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return "The user service manager isn't available, so the timer may not go off."
    if p.returncode == 0:
        return ""
    try:
        arm(t.get("gen", ""), t["deadline"])
    except Failed as exc:
        return f"The timer's alert was lost and couldn't be set again ({exc})."
    return ""


def status() -> int:
    try:
        with locked():
            data = load()
            problem = reconcile(data)
    except Failed as exc:
        return say(False, error=str(exc))
    return say(True, alarms=sorted(data.get("alarms", []), key=lambda a: a.get("time", "")),
               timer=timer_state(data), now=time.time(), **({"note": problem} if problem else {}))


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
    if cmd == "fire-timer" and len(args) <= 1:
        return fire_timer(args[0] if args else "")
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
