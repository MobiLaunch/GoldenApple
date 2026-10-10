#!/usr/bin/env python3
"""Persistent local event store for CitronOS Calendar.

    helper.py list            {"ok", "events", "invalid"} or {"ok": false, "broken": true, …}
    helper.py add  < EVENT    add {"title", "date": YYYY-MM-DD, "time": "" | HH:MM, "calendar"}
    helper.py edit ID < EVENT  save changes only if the original is current
    helper.py duplicate ID    make a separately editable copy
    Supports never/daily/weekly/monthly/yearly, optional inclusive end date
    helper.py occurrence-edit ID DATE < EVENT    change just one series instance
    helper.py occurrence-skip ID DATE < EVENT    skip one series instance
    helper.py occurrence-reset ID DATE < EVENT   restore a skipped/edited date
    helper.py delete ID
    helper.py restore         put the last good copy back after the store broke

Events live in events.json. A missing file is an empty calendar; a file that
can't be read or parsed is not: it's left exactly as it is, Calendar says so,
and nothing is written over it until it's restored from events.json.bak (the
store as it was before the last change), with the broken file kept beside it.
Every change reads, edits and writes the store under one lock, so two windows
adding at once both keep their events. A date is a real calendar date; a time
is a 24-hour HH:MM in the computer's time zone, or empty for all day."""
from __future__ import annotations
import contextlib
import datetime
import fcntl
import json
import os
import pathlib
import shutil
import sys
import tempfile
import uuid

ROOT = pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")) / "golden-gate/calendar"
PATH = ROOT / "events.json"
BACKUP = ROOT / "events.json.bak"
LOCK = ROOT / ".events.lock"


REPEATS = frozenset(("never", "daily", "weekly", "monthly", "yearly"))
REMINDERS = frozenset((-1, 0, 5, 15, 60))


class Broken(Exception):
    """The store exists but can't be used; nothing may replace it."""


def check(event: dict) -> str:
    """Why an event can't be stored, or ""."""
    if not isinstance(event, dict):
        return "An event must be a record."
    title = event.get("title")
    if not isinstance(title, str) or not title.strip():
        return "Enter an event name."
    if len(title) > 500:
        return "Use a shorter event name."
    date = event.get("date")
    try:
        if not isinstance(date, str) or len(date) != 10:
            raise ValueError
        datetime.date.fromisoformat(date)
    except ValueError:
        return "Enter a date as YYYY-MM-DD, such as 2026-10-07."
    time = event.get("time", "")
    if time:
        try:
            if not isinstance(time, str) or len(time) != 5:
                raise ValueError
            datetime.time.fromisoformat(time)
        except ValueError:
            return "Enter a time as HH:MM on a 24-hour clock, such as 14:30, or leave it empty for all day."
    calendar = event.get("calendar", "Home")
    if not isinstance(calendar, str) or not calendar.strip() or len(calendar) > 64:
        return "Choose a calendar."
    repeat = event.get("repeat", "never")
    if not isinstance(repeat, str) or repeat not in REPEATS:
        return "Repeat must be Never, Daily, Weekly, Monthly, or Yearly."
    until = event.get("until", "")
    if until:
        if not isinstance(until, str) or len(until) != 10:
            return "Enter a repeat end date as YYYY-MM-DD, or leave it empty."
        try:
            datetime.date.fromisoformat(until)
        except ValueError:
            return "Enter a real repeat end date as YYYY-MM-DD."
        if repeat == "never":
            return "Choose a repeat interval before setting an end date."
        if until < date:
            return "The repeat end date must not be before the first event."
    reminder = event.get("reminder", -1)
    if type(reminder) is not int or reminder not in REMINDERS:
        return "Choose no reminder, at event time, or 5, 15, or 60 minutes before."
    exceptions = event.get("exceptions", {})
    if not isinstance(exceptions, dict) or len(exceptions) > 1500:
        return "The occurrence exceptions are damaged or exceed the supported limit."
    for original, override in exceptions.items():
        try:
            start_date = datetime.date.fromisoformat(original)
        except (TypeError, ValueError):
            return "An occurrence exception has an invalid original date."
        if not isinstance(original, str) or len(original) != 10 or not occurs_on(event, start_date):
            return "An occurrence exception is not part of this series."
        if override is None:
            continue
        if not isinstance(override, dict) or set(override) - {"title", "date", "time", "calendar", "reminder"}:
            return "An occurrence override is damaged."
        revised = {"title": override.get("title"), "date": override.get("date"),
                   "time": override.get("time", ""), "calendar": override.get("calendar", "Home")}
        # Validate occurrence fields, not a nested recurring series.
        if not isinstance(revised["title"], str) or not revised["title"].strip() or len(revised["title"]) > 500:
            return "An occurrence override needs a valid title."
        try:
            if not isinstance(revised["date"], str) or len(revised["date"]) != 10:
                raise ValueError
            datetime.date.fromisoformat(revised["date"])
            if revised["time"]:
                if not isinstance(revised["time"], str) or len(revised["time"]) != 5:
                    raise ValueError
                datetime.time.fromisoformat(revised["time"])
        except ValueError:
            return "An occurrence override has an invalid date or time."
        if not isinstance(revised["calendar"], str) or not revised["calendar"].strip() or len(revised["calendar"]) > 64:
            return "An occurrence override needs a valid calendar."
        per_reminder = override.get("reminder", reminder)
        if type(per_reminder) is not int or per_reminder not in REMINDERS:
            return "An occurrence override has an invalid reminder."
    return ""


def parse(raw: bytes) -> list:
    """The store's contract, for events.json and any copy that would replace
    it: UTF-8 JSON holding a list. Raises Broken otherwise."""
    try:
        data = json.loads(raw.decode("utf-8"))
    except ValueError as exc:                    # bad JSON or bad UTF-8
        raise Broken("Calendar's events file is damaged.") from exc
    if not isinstance(data, list):
        raise Broken("Calendar's events file is damaged.")
    return data


def load() -> list:
    """Every stored record (valid or not, so none is lost on the next save).
    Raises Broken if the store is there but unusable."""
    try:
        raw = PATH.read_bytes()
    except FileNotFoundError:
        return []
    except OSError as exc:
        raise Broken(f"Calendar can't read its events ({exc.strerror or exc}).") from exc
    return parse(raw)


def save(events: list) -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    if PATH.exists():
        shutil.copy2(PATH, BACKUP)
    install((json.dumps(events, indent=1) + "\n").encode("utf-8"))


def install(raw: bytes) -> None:
    """events.json becomes raw, all at once."""
    fd, name = tempfile.mkstemp(prefix=".events.", suffix=".json", dir=ROOT)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, PATH)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


@contextlib.contextmanager
def locked():
    ROOT.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def keep_broken() -> pathlib.Path | None:
    """A copy of the damaged store under a name of its own (two restores in
    the same second each keep theirs), left beside it."""
    if not PATH.exists():
        return None
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    n = 1
    while True:
        kept = ROOT / (f"events.broken-{stamp}.json" if n == 1 else f"events.broken-{stamp}-{n}.json")
        n += 1
        try:
            with open(kept, "xb") as out:
                out.write(PATH.read_bytes())
                out.flush()
                os.fsync(out.fileno())
            return kept
        except FileExistsError:
            continue


def emit(ok: bool, **data: object) -> int:
    print(json.dumps({"ok": ok, **data}, separators=(",", ":")))
    return 0 if ok else 1


def broken(exc: Broken) -> int:
    return emit(False, broken=True, canRestore=BACKUP.exists(),
                error=f"{exc} It has been left as it is; nothing will be saved over it."
                      + (" Choose Restore to go back to the last good copy." if BACKUP.exists() else ""))



def occurs_on(event: dict, day: datetime.date) -> bool:
    """The *base* series recurrence, before exceptions and moved instances."""
    try:
        first = datetime.date.fromisoformat(event["date"])
        end = datetime.date.fromisoformat(event["until"]) if event.get("until") else None
    except (KeyError, TypeError, ValueError):
        return False
    if day < first or (end is not None and day > end):
        return False
    interval = event.get("repeat", "never")
    if interval == "never":
        return day == first
    if interval == "daily":
        return True
    if interval == "weekly":
        return (day - first).days % 7 == 0
    if interval == "monthly":
        return first.day == day.day
    if interval == "yearly":
        return first.month == day.month and first.day == day.day
    return False


def expected_event_matches(old: dict, expected: dict) -> bool:
    """Optimistic lock: preserves compatibility with old snapshot shapes."""
    return all(old.get(k, default) == expected.get(k, default) for k, default in
               (("title", None), ("date", None), ("time", ""),
                ("calendar", "Home"), ("repeat", "never"), ("until", ""),
                ("exceptions", {}), ("reminder", -1)))

def sort_key(e: object) -> tuple:
    e = e if isinstance(e, dict) else {}
    return (str(e.get("date", "")), str(e.get("time", "")), str(e.get("title", "")))


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    command = sys.argv[1]

    if command == "list":
        try:
            with locked():
                events = load()
                remote = []
                remote_error = ""
                cache = ROOT / "caldav-events.json"
                try:
                    raw = json.loads(cache.read_text(encoding="utf-8"))
                    if not isinstance(raw, list) or len(raw) > 5000:
                        raise ValueError("unexpected cache format")
                    if any(not isinstance(e, dict) or e.get("remote") is not True or
                           not isinstance(e.get("id"), str) or not e["id"].startswith("caldav-") or
                           check(e) for e in raw):
                        raise ValueError("invalid remote calendar events")
                    remote = raw
                except FileNotFoundError:
                    pass
                except (ValueError, OSError) as exc:
                    remote_error = f"CalDAV cache could not be read ({exc}). Local events are unaffected."
        except Broken as exc:
            return broken(exc)
        good = [e for e in events if not check(e)]
        extra = {"remoteError": remote_error} if remote_error else {}
        return emit(True, events=sorted(good + remote, key=sort_key),
                    invalid=len(events) - len(good), **extra)

    if command == "add":
        try:
            event = json.load(sys.stdin)
        except ValueError:
            return emit(False, error="The event could not be read.")
        if not isinstance(event, dict):
            return emit(False, error="The event could not be read.")
        row = {
            "title": str(event.get("title") or "").strip(),
            "date": str(event.get("date") or "").strip(),
            "time": str(event.get("time") or "").strip(),
            "calendar": str(event.get("calendar") or "Home").strip(),
            "repeat": str(event.get("repeat", "never")).strip().lower(),
            "until": str(event.get("until", "")).strip(),
            "reminder": event.get("reminder", -1),
        }
        problem = check(row)
        if problem:
            return emit(False, error=problem)
        row = {"id": uuid.uuid4().hex, **row}
        try:
            with locked():
                events = load()
                events.append(row)
                events.sort(key=sort_key)
                save(events)
        except Broken as exc:
            return broken(exc)
        except OSError as exc:
            return emit(False, error=f"The event could not be saved ({exc.strerror or exc}).")
        return emit(True, event=row)

    if command == "edit" and len(sys.argv) == 3:
        target = sys.argv[2]
        try:
            event = json.load(sys.stdin)
        except ValueError:
            return emit(False, error="The edited event could not be read.")
        if not isinstance(event, dict) or not isinstance(event.get("expected"), dict):
            return emit(False, error="Reopen this event before editing it.")
        expected = event["expected"]
        if expected.get("id") != target:
            return emit(False, error="Reopen this event before editing it.")
        changes = {
            "title": str(event.get("title") or "").strip(),
            "date": str(event.get("date") or "").strip(),
            "time": str(event.get("time") or "").strip(),
            "calendar": str(event.get("calendar") or "Home").strip(),
            "repeat": str(event.get("repeat", "never")).strip().lower(),
            "until": str(event.get("until", "")).strip(),
            "reminder": event.get("reminder", -1),
        }
        problem = check(changes)
        if problem:
            return emit(False, error=problem)
        try:
            with locked():
                events = load()
                matches = [i for i, item in enumerate(events)
                           if isinstance(item, dict) and item.get("id") == target]
                if len(matches) != 1:
                    return emit(False, error="That event is missing or has an ambiguous identity. Refresh Calendar.")
                index = matches[0]
                old = events[index]
                if not expected_event_matches(old, expected):
                    return emit(False, conflict=True,
                                error="This event changed in another window. Close the editor and reopen it to see the latest version.")
                if old.get("exceptions") and (old.get("date") != changes["date"] or old.get("repeat", "never") != changes["repeat"] or old.get("until", "") != changes["until"]):
                    return emit(False, error="Remove or reset individual changes before changing this series’ recurrence.")
                edited = {**old, **changes}
                events[index] = edited
                events.sort(key=sort_key)
                save(events)
        except Broken as exc:
            return broken(exc)
        except OSError as exc:
            return emit(False, error=f"The edited event could not be saved ({exc.strerror or exc}).")
        return emit(True, event=edited)

    if command in ("occurrence-edit", "occurrence-skip") and len(sys.argv) == 4:
        target, original = sys.argv[2], sys.argv[3]
        try:
            request = json.load(sys.stdin)
        except ValueError:
            return emit(False, error="The occurrence request could not be read.")
        if not isinstance(request, dict) or not isinstance(request.get("expected"), dict):
            return emit(False, error="Reopen the event to edit this occurrence.")
        try:
            day = datetime.date.fromisoformat(original)
            if len(original) != 10:
                raise ValueError
        except ValueError:
            return emit(False, error="The selected occurrence date is invalid.")
        try:
            with locked():
                events = load()
                matches = [i for i, e in enumerate(events) if isinstance(e, dict) and e.get("id") == target]
                if len(matches) != 1:
                    return emit(False, error="That series is missing or duplicated. Refresh Calendar.")
                i = matches[0]
                old = events[i]
                if old.get("repeat", "never") == "never" or not occurs_on(old, day):
                    return emit(False, error="This date is not an occurrence of the repeating event.")
                if request["expected"].get("id") != target or not expected_event_matches(old, request["expected"]):
                    return emit(False, conflict=True,
                                error="This repeating event changed in another window. Reopen it before editing.")
                exceptions = dict(old.get("exceptions") or {})
                if command == "occurrence-skip":
                    exceptions[original] = None
                else:
                    revised = {"title": request.get("title"), "date": request.get("date"),
                               "time": request.get("time", ""), "calendar": request.get("calendar", "Home"),
                               "reminder": request.get("reminder", old.get("reminder", -1))}
                    proposed = {**old, "exceptions": {**exceptions, original: revised}}
                    problem = check(proposed)
                    if problem:
                        return emit(False, error=problem)
                    exceptions[original] = revised
                changed = {**old, "exceptions": exceptions}
                problem = check(changed)
                if problem:
                    return emit(False, error=problem)
                events[i] = changed
                save(events)
        except Broken as exc:
            return broken(exc)
        except OSError as exc:
            return emit(False, error=f"The occurrence could not be saved ({exc.strerror or exc}).")
        return emit(True, event=changed)

    if command == "occurrence-reset" and len(sys.argv) == 4:
        target, original = sys.argv[2], sys.argv[3]
        try:
            request = json.load(sys.stdin)
        except ValueError:
            return emit(False, error="The occurrence request could not be read.")
        if not isinstance(request, dict) or not isinstance(request.get("expected"), dict):
            return emit(False, error="Reopen the event first.")
        try:
            with locked():
                events = load()
                matches = [i for i, e in enumerate(events) if isinstance(e, dict) and e.get("id") == target]
                if len(matches) != 1:
                    return emit(False, error="That series is missing or duplicated.")
                old = events[matches[0]]
                if request["expected"].get("id") != target or not expected_event_matches(old, request["expected"]):
                    return emit(False, conflict=True, error="This series changed. Refresh Calendar.")
                if original not in (old.get("exceptions") or {}):
                    return emit(False, error="There is no change to reset on that date.")
                exceptions = dict(old["exceptions"])
                del exceptions[original]
                changed = {**old, "exceptions": exceptions}
                events[matches[0]] = changed
                save(events)
        except Broken as exc:
            return broken(exc)
        except OSError as exc:
            return emit(False, error=f"Could not restore the occurrence ({exc.strerror or exc}).")
        return emit(True, event=changed)

    if command == "duplicate" and len(sys.argv) == 3:
        target = sys.argv[2]
        try:
            with locked():
                events = load()
                matches = [item for item in events
                           if isinstance(item, dict) and item.get("id") == target]
                if len(matches) != 1:
                    return emit(False, error="That event is missing or has an ambiguous identity. Refresh Calendar.")
                source = matches[0]
                if check(source):
                    return emit(False, error="That event is damaged and cannot be duplicated.")
                copied = {**source, "id": uuid.uuid4().hex,
                          "title": ("Copy of " + source["title"])[:500]}
                events.append(copied)
                events.sort(key=sort_key)
                save(events)
        except Broken as exc:
            return broken(exc)
        except OSError as exc:
            return emit(False, error=f"The event could not be duplicated ({exc.strerror or exc}).")
        return emit(True, event=copied)

    if command == "delete" and len(sys.argv) == 3:
        target = sys.argv[2]
        try:
            with locked():
                events = load()
                newer = [e for e in events if not (isinstance(e, dict) and e.get("id") == target)]
                if len(newer) == len(events):
                    return emit(False, error="That event no longer exists.")
                save(newer)
        except Broken as exc:
            return broken(exc)
        except OSError as exc:
            return emit(False, error=f"The event could not be deleted ({exc.strerror or exc}).")
        return emit(True)

    if command == "restore":
        with locked():
            try:
                load()
                return emit(True, restored=False)        # nothing to restore
            except Broken:
                pass
            if not BACKUP.exists():
                return emit(False, error="There's no earlier copy to restore.")
            # The copy must pass the same check as the store itself, or the
            # store stays as it is: a restore never puts back something that
            # would be damaged again on the next look.
            try:
                raw = BACKUP.read_bytes()
                parse(raw)
            except OSError as exc:
                return emit(False, error=f"The earlier copy can't be read ({exc.strerror or exc}).")
            except Broken:
                return emit(False, error="The earlier copy is damaged too. Nothing was changed.")
            try:
                kept = keep_broken()
                install(raw)                     # the bytes that were checked, not the file again
            except OSError as exc:
                return emit(False, error=f"The earlier copy couldn't be put back ({exc.strerror or exc}).")
            return emit(True, restored=True, kept=str(kept) if kept else "")

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
