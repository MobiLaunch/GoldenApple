#!/usr/bin/env python3
"""Change some keys of one Settings record, and only those keys.

    set-prefs.py privacy       KEY=JSON ...   privacy.json
    set-prefs.py input         KEY=JSON ...   input.json, and hypr's input.conf from it
    set-prefs.py accessibility KEY=JSON ...   accessibility.json, and hypr's accessibility.conf
    set-prefs.py windows       KEY=JSON ...   windows.json, and hypr's windows.conf

Under the record's lock it reads the latest saved record, changes the keys
given and nothing else, and replaces the file atomically; so two Settings
windows (or Settings and anything else) changing different keys at once
both keep their change, and a window with an old copy can't write it back.
A record whose file is damaged is left as it is and the change refused, so
nothing already saved is lost to a guess.

input.conf and accessibility.conf are generated from the merged record and
put in place with it, under the same lock: if the .conf can't be, the record
is put back as it was, so they never disagree.

Prints {"ok": true, "record": {...}} (the record as saved) or
{"ok": false, "error": "..."}; the exit status says the same."""
from __future__ import annotations

import fcntl
import json
import os
import pathlib
import re
import sys
import tempfile

CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")
GG = CONFIG / "golden-gate"
HYPR = CONFIG / "hypr/golden-gate"
KEY = re.compile(r"[A-Za-z][A-Za-z0-9_]{0,63}$")


class Refused(Exception):
    pass


def say(ok: bool, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")))
    return 0 if ok else 1


def read_record(path: pathlib.Path) -> tuple[dict, bytes | None]:
    """The record and the bytes it came from (None: there was no file)."""
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return {}, None
    except OSError as exc:
        raise Refused(f"{path.name} can't be read ({exc.strerror or exc})")
    try:
        data = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise Refused(f"{path.name} is damaged, so it was left as it is")
    if not isinstance(data, dict):
        raise Refused(f"{path.name} is damaged, so it was left as it is")
    return data, raw


def staged(target: pathlib.Path, data: bytes) -> str:
    """data in a temporary file beside target, on disk, ready to rename over it."""
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, target.stat().st_mode & 0o777)
        except FileNotFoundError:
            os.chmod(tmp, 0o644)
    except BaseException:
        os.unlink(tmp)
        raise
    return tmp


def put_back(path: pathlib.Path, raw: bytes | None) -> None:
    try:
        if raw is None:
            path.unlink(missing_ok=True)
        else:
            os.replace(staged(path, raw), path)
    except OSError:
        pass                                    # as good as it can be made


def setup_keyboard() -> dict:
    """input.conf's layout and variant from Setup Assistant, the first time
    input.json is written, so a change of repeat rate keeps the keyboard."""
    seed = {}
    try:
        for line in (HYPR / "input.conf").read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*(kb_layout|kb_variant)\s*=\s*(.*?)\s*$", line)
            if m:
                seed["layout" if m.group(1) == "kb_layout" else "variant"] = m.group(2)
    except OSError:
        pass
    if not seed.get("layout"):
        seed.pop("layout", None)
    return seed


def input_conf(i: dict) -> str:
    def num(key, default):
        v = i.get(key, default)
        return v if isinstance(v, (int, float)) and not isinstance(v, bool) else default

    def flag(key):
        return "false" if i.get(key, True) is False else "true"

    def word(key, default):
        v = i.get(key, default)
        return v if isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_(),+-]*", v) else default
    return ("input {\n"
            f"    kb_layout = {word('layout', 'us') or 'us'}\n"
            f"    kb_variant = {word('variant', '')}\n"
            f"    repeat_rate = {round(num('repeatRate', 25))}\n"
            f"    repeat_delay = {round(num('repeatDelay', 600))}\n"
            f"    sensitivity = {num('sensitivity', 0):.2f}\n"
            "    touchpad {\n"
            f"        natural_scroll = {flag('naturalScroll')}\n"
            f"        tap-to-click = {flag('tapToClick')}\n"
            f"        clickfinger_behavior = {flag('twoFingerClick')}\n"
            f"        disable_while_typing = {flag('disableWhileTyping')}\n"
            f"        tap_and_drag = {flag('tapAndDrag')}\n"
            f"        drag_lock = {max(0, min(2, round(num('dragLock', 0))))}\n"
            f"        scroll_factor = {max(0.3, min(3.0, num('scrollFactor', 0.6))):.2f}\n"
            "    }\n}\n")


def windows_conf(w: dict) -> str:
    """Compositor-native floating-window snapping and resize affordances.

    Validate every scalar before interpolation, preventing both config injection
    and impossible compositor values even if another writer modifies JSON.
    """
    def flag(key: str, default: bool) -> str:
        val = w.get(key, default)
        return "true" if val is True or (val is not False and default) else "false"

    def integer(key: str, default: int) -> int:
        val = w.get(key, default)
        if not isinstance(val, (float, int)) or isinstance(val, bool):
            return default
        return max(0, min(100, round(val)))

    return (
        "# Generated by Golden Gate Settings. Do not hand-edit.\n"
        "general {\n"
        f"    resize_on_border = {flag('resizeOnBorder', True)}\n"
        f"    extend_border_grab_area = {integer('grabArea', 12)}\n"
        "    snap {\n"
        f"        enabled = {flag('snapEnabled', True)}\n"
        f"        window_gap = {integer('windowGap', 12)}\n"
        f"        monitor_gap = {integer('monitorGap', 12)}\n"
        f"        border_overlap = false\n"
        f"        respect_gaps = {flag('respectGaps', True)}\n"
        "    }\n"
        "}\n"
    )


def accessibility_conf(a: dict) -> str:
    return "animations {\n    enabled = %s\n}\n" % ("false" if a.get("reduceMotion") is True else "true")


RECORDS = {
    # name: (record file, generated file and how, first-time seed)
    "privacy": (GG / "privacy.json", None, None),
    "input": (GG / "input.json", (HYPR / "input.conf", input_conf), setup_keyboard),
    "accessibility": (GG / "accessibility.json", (HYPR / "accessibility.conf", accessibility_conf), None),
    "windows": (GG / "windows.json", (HYPR / "windows.conf", windows_conf), None),
}


def change(name: str, changes: dict) -> dict:
    path, generated, seed = RECORDS[name]
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.parent / f".{path.name}.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        record, raw = read_record(path)
        if raw is None and seed:
            record = seed()
        record.update(changes)
        json_tmp = staged(path, (json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
        conf_tmp = None
        try:
            if generated:
                conf_tmp = staged(generated[0], generated[1](record).encode("utf-8"))
            os.replace(json_tmp, path)
            if conf_tmp:
                try:
                    os.replace(conf_tmp, generated[0])
                except OSError:
                    put_back(path, raw)         # the two never disagree
                    raise
        finally:
            for t in (json_tmp, conf_tmp):
                if t:
                    try:
                        os.unlink(t)
                    except FileNotFoundError:
                        pass
        return record


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in RECORDS:
        print(__doc__, file=sys.stderr)
        return say(False, error="usage: set-prefs.py privacy|input|accessibility|windows KEY=JSON ...")
    changes = {}
    for arg in argv[2:]:
        key, sep, raw = arg.partition("=")
        if not sep or not KEY.match(key):
            return say(False, error=f"Not a setting: {arg}")
        try:
            changes[key] = json.loads(raw)
        except ValueError:
            return say(False, error=f"Not a value: {arg}")
    try:
        record = change(argv[1], changes)
    except Refused as exc:
        return say(False, error=str(exc))
    except OSError as exc:
        return say(False, error=exc.strerror or str(exc))
    return say(True, record=record)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
