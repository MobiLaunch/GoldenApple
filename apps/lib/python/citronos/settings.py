"""CitronOS's typed preferences (T-2.5): one file per domain in
~/.config/golden-gate, a schema giving every key a type and a default
(settings-schema.json), and the last good copy kept beside each (.bak).

    store = settings.Store("desktop")
    store.get("dock.size")                  # 54 if it was never set
    store.set("dock.size", 64)              # checked, locked, atomic
    store.set("dock.size", "big")           # SettingsError(code="invalid")

A file found damaged (unreadable, or not a set of preferences) is put back
from its last good copy, the damaged one kept aside, and the store reports
it (store.notice) so whoever changed something can say so. With no good copy
to restore it's left as it is and every write is refused: starting again
from {} would throw away every other preference on a guess.
"""
from __future__ import annotations

import datetime
import json
from pathlib import Path

from . import files, paths

SCHEMA = json.loads(Path(__file__).with_name("settings-schema.json").read_text(encoding="utf-8"))
_MISSING = object()


class SettingsError(Exception):
    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code     # invalid | unknown | damaged


def _node(schema: dict, part: str) -> dict | None:
    """The schema for a child of an object schema, or None if it has none."""
    if schema.get("type") not in ("object",) and schema.get("type") != "any":
        return None
    if schema.get("type") == "any":
        return {"type": "any"}
    return (schema.get("keys") or {}).get(part) or schema.get("values")


def schema_for(domain: str, key: str) -> dict:
    node = SCHEMA[domain]
    for part in key.split("."):
        child = _node(node, part)
        if child is None:
            raise SettingsError(f"{key} isn't a {domain} preference.", "unknown")
        node = child
    return node


def check(schema: dict, value, where: str) -> None:
    """Raises SettingsError if value doesn't fit schema."""
    kind = schema.get("type", "any")
    if value is None:
        if schema.get("nullable") or kind == "any":
            return
        raise SettingsError(f"{where} can't be empty.", "invalid")
    ok = {
        "any": lambda v: True,
        "bool": lambda v: isinstance(v, bool),
        "int": lambda v: isinstance(v, int) and not isinstance(v, bool),
        "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
        "string": lambda v: isinstance(v, str),
        "list": lambda v: isinstance(v, list),
        "object": lambda v: isinstance(v, dict),
    }[kind](value)
    if not ok:
        raise SettingsError(f"{where} should be {'a' if kind not in ('int', 'object') else 'an'} {kind}.", "invalid")
    if kind in ("int", "number"):
        if "min" in schema and value < schema["min"] or "max" in schema and value > schema["max"]:
            raise SettingsError(f"{where} should be between {schema.get('min')} and {schema.get('max')}.", "invalid")
    if kind == "string" and "enum" in schema and value not in schema["enum"]:
        raise SettingsError(f"{where} should be one of {', '.join(schema['enum'])}.", "invalid")
    if kind == "list" and "items" in schema:
        for i, item in enumerate(value):
            check(schema["items"], item, f"{where}[{i}]")
    if kind == "object":
        for k, v in value.items():
            child = (schema.get("keys") or {}).get(k) or schema.get("values")
            if child is None:
                raise SettingsError(f"{where}.{k} isn't a preference.", "unknown")
            check(child, v, f"{where}.{k}")


def default(domain: str, key: str):
    return schema_for(domain, key).get("default")


class Store:
    def __init__(self, domain: str, folder: Path | None = None):
        if domain not in SCHEMA or domain.startswith("_"):
            raise SettingsError(f"There are no {domain} preferences.", "unknown")
        self.domain = domain
        self.folder = Path(folder) if folder else paths.config()
        self.file = self.folder / f"{domain}.json"
        self.backup = self.folder / f"{domain}.json.bak"
        self.lock = self.folder / f".{domain}.json.lock"
        self.notice = ""        # set when a damaged file was put back

    def _parse(self, raw: bytes) -> dict:
        value = json.loads(raw.decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("it isn't a set of preferences")
        return value

    def peek(self) -> dict:
        """The preferences as saved, repairing nothing (a watcher's read):
        SettingsError("damaged") if they can't be read."""
        try:
            return self._parse(self.file.read_bytes())
        except FileNotFoundError:
            return {}
        except (OSError, ValueError, UnicodeError) as exc:
            raise SettingsError(f"{self.file.name} can't be read ({exc}).", "damaged") from None

    def load(self) -> dict:
        """The preferences as saved, after putting back a damaged file from
        its last good copy (call under the lock to change them)."""
        try:
            raw = self.file.read_bytes()
        except FileNotFoundError:
            return {}
        except OSError as exc:
            raise SettingsError(f"{self.file.name} can't be read ({exc.strerror or exc}).", "damaged")
        try:
            return self._parse(raw)
        except (ValueError, UnicodeError) as damage:
            kept = self._keep_damaged(raw)
            try:
                good_raw = self.backup.read_bytes()
                good = self._parse(good_raw)
            except (OSError, ValueError, UnicodeError):
                raise SettingsError(
                    f"{self.file.name} is damaged ({damage}) and there's no good copy to put back, so it was "
                    f"left as it is" + (f"; a copy is in {kept.name}" if kept else "") + ".", "damaged") from None
            files.atomic_write(self.file, good_raw)
            when = datetime.datetime.fromtimestamp(self.backup.stat().st_mtime).strftime("%-d %b %H:%M")
            self.notice = (f"Your {self.domain} preferences were damaged, so the copy saved {when} was put "
                           f"back" + (f"; the damaged file is in {kept.name}" if kept else "") + ".")
            return good

    def _keep_damaged(self, raw: bytes) -> Path:
        """One copy of the damaged file for repair, however often it's met:
        desktop.json.damaged-20261026-101500, reused while the content's the same."""
        for copy in sorted(self.folder.glob(f"{self.file.name}.damaged-*")):
            try:
                if copy.read_bytes() == raw:
                    return copy
            except OSError:
                continue
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        n = 1
        while True:
            copy = self.folder / f"{self.file.name}.damaged-{stamp}{'' if n == 1 else f'-{n}'}"
            n += 1
            try:
                with open(copy, "xb") as out:
                    out.write(raw)
                return copy
            except FileExistsError:
                continue

    def check_file(self) -> str:
        """Puts a damaged file back if it can (at login, say); the notice, or ""."""
        with files.locked(self.lock):
            self.load()
        return self.notice

    def get(self, key: str):
        node = self.load()
        for part in key.split("."):
            node = node.get(part, _MISSING) if isinstance(node, dict) else _MISSING
            if node is _MISSING:
                return default(self.domain, key)
        return node

    def set(self, key: str, value) -> dict:
        """Saves one key (dotted), checked against the schema, under the
        store's lock; the file as it was becomes the last good copy."""
        parts = [p for p in key.split(".") if p]
        if not parts:
            raise SettingsError("Which preference?", "unknown")
        check(schema_for(self.domain, ".".join(parts)), value, ".".join(parts))
        with files.locked(self.lock):
            data = self.load()
            node = data
            for part in parts[:-1]:
                child = node.get(part)
                if not isinstance(child, dict):
                    child = {}
                    node[part] = child
                node = child
            node[parts[-1]] = value
            files.atomic_json(self.file, data, backup=self.backup if self.file.exists() else None)
        return data
