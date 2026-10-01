#!/usr/bin/env python3
"""Persistent local event store for Golden Gate Calendar."""
from __future__ import annotations
import json
import os
import pathlib
import sys
import tempfile
import uuid

ROOT = pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share")) / "golden-gate/calendar"
PATH = ROOT / "events.json"


def load() -> list[dict]:
    try:
        data = json.loads(PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save(events: list[dict]) -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".events.", suffix=".json", dir=ROOT)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(events, f, indent=1)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, PATH)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def emit(ok: bool, **data: object) -> int:
    print(json.dumps({"ok": ok, **data}, separators=(",", ":")))
    return 0 if ok else 1


def main() -> int:
    if len(sys.argv) < 2:
        return 2

    if sys.argv[1] == "list":
        return emit(True, events=load())

    if sys.argv[1] == "add":
        try:
            event = json.load(sys.stdin)
            title = str(event.get("title") or "").strip()
            date = str(event.get("date") or "").strip()
            time = str(event.get("time") or "").strip()
            calendar = str(event.get("calendar") or "Home").strip()
            if not title or len(date) != 10:
                return emit(False, error="Enter an event name and date.")
            row = {
                "id": uuid.uuid4().hex,
                "title": title,
                "date": date,
                "time": time,
                "calendar": calendar,
            }
            events = load()
            events.append(row)
            events.sort(key=lambda e: (e.get("date", ""), e.get("time", ""), e.get("title", "")))
            save(events)
            return emit(True, event=row)
        except Exception as exc:
            return emit(False, error=str(exc))

    if sys.argv[1] == "delete" and len(sys.argv) == 3:
        target = sys.argv[2]
        events = load()
        newer = [e for e in events if e.get("id") != target]
        if len(newer) == len(events):
            return emit(False, error="That event no longer exists.")
        save(newer)
        return emit(True)

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
