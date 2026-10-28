#!/usr/bin/env python3
"""citronos-notifyd: CitronOS's notifications and app badges (T-2.6, CS2-024).

Apps send notifications to it (org.freedesktop.Notifications, the standard
every toolkit uses). It keeps them in a history that outlives the shell
(SQLite in ~/.local/state/golden-gate), applies each app's choice in Settings
(an app that isn't allowed is dropped), and marks the ones Focus keeps quiet.
The shell shows them, as banners and in Notification Center, as a client:

    org.citronos.Notifications1 at /org/citronos/Notifications1, as JSON text:
      List() → [notification]       newest first
      Dismiss(id)                   gone, as the user's doing (reason 2)
      DismissApp(key)               all of one app's ("" for all)
      Invoke(id, action)            the app hears ActionInvoked; it's done
                                    with unless it's resident
      Badges() → {app: badge}
      Added(notification)           new, or replacing one with the same id
      Removed(id, reason)
      BadgesChanged(badges)

Badges and progress come from the de-facto standard most Electron, Qt and
GTK apps use, com.canonical.Unity.LauncherEntry: an app broadcasts
Update("application://its.desktop", {count, count-visible, progress,
progress-visible, urgent}) and its Dock icon shows them until the app says
otherwise or leaves the bus.

Started by D-Bus activation (either name), or with the session, as the user
unit citronos-notifyd.service.
"""
import asyncio
import json
import os
from pathlib import Path
import sqlite3
import struct
import sys
import time
import zlib

HERE = Path(__file__).resolve()
for candidate in (HERE.parents[2] / "apps/lib/python", HERE.parents[1] / "apps/lib/python",
                  Path("/usr/share/golden-gate/ui/python")):
    if (candidate / "citronos").is_dir():
        sys.path.insert(0, str(candidate))
        break
from citronos import files, focus, paths, settings  # noqa: E402

from dbus_next import BusType, Message, MessageType, RequestNameReply, Variant  # noqa: E402
from dbus_next.aio import MessageBus  # noqa: E402
from dbus_next.constants import NameFlag  # noqa: E402
from dbus_next.service import ServiceInterface, method, signal  # noqa: E402

FDO = ("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
OURS = ("org.citronos.Notifications1", "/org/citronos/Notifications1")
LAUNCHER = "com.canonical.Unity.LauncherEntry"
DBUS = ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus")
HISTORY = 300                     # notifications kept in Notification Center
EXPIRED, DISMISSED, CLOSED = 1, 2, 3
# Services that notify on an app's behalf: BlueFerry delivers Messages' iPhone messages.
OWNERS = {"blueferry": "org.goldengate.Messages", "io.weirdware.blueferry": "org.goldengate.Messages"}
MAX_IMAGE = 2048 * 2048 * 4


def plain(value):
    if isinstance(value, Variant):
        return plain(value.value)
    if isinstance(value, (list, tuple)):
        return [plain(v) for v in value]
    if isinstance(value, dict):
        return {str(k): plain(v) for k, v in value.items()}
    return value


def owner_of(app_name: str, desktop_entry: str) -> str:
    entry = desktop_entry.lower().removesuffix(".desktop")
    return OWNERS.get(entry) or OWNERS.get(app_name.lower()) or ""


def key_of(app_name: str, desktop_entry: str) -> str:
    """One name per app for its Notifications settings (as the shell's keyOf)."""
    return focus.canonical_app(owner_of(app_name, desktop_entry) or desktop_entry or app_name or "notification")


def png(width: int, height: int, rowstride: int, alpha: bool, data: bytes) -> bytes:
    """An image-data hint (raw RGB or RGBA rows) as a PNG file."""
    channels = 4 if alpha else 3
    rows = b"".join(b"\0" + data[y * rowstride:y * rowstride + width * channels] for y in range(height))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 6 if alpha else 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")


class Store:
    """The history: what Notification Center shows, kept across restarts."""

    def __init__(self, folder: Path):
        folder.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(folder / "notifications.db", isolation_level=None)
        os.chmod(folder / "notifications.db", 0o600)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY, received INTEGER, record TEXT)")
        self.db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value INTEGER)")

    def all(self) -> list[dict]:
        rows = self.db.execute("SELECT record FROM notifications ORDER BY received DESC, id DESC").fetchall()
        out = []
        for (raw,) in rows:
            try:
                out.append(json.loads(raw))
            except ValueError:
                continue
        return out

    def last_id(self) -> int:
        row = self.db.execute("SELECT value FROM meta WHERE key = 'last_id'").fetchone()
        return row[0] if row else 0

    def set_last_id(self, value: int) -> None:
        self.db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('last_id', ?)", (value,))

    def put(self, record: dict) -> list[int]:
        """Saves one; returns the ids pushed out by the limit."""
        self.db.execute("INSERT OR REPLACE INTO notifications (id, received, record) VALUES (?, ?, ?)",
                        (record["id"], record["received"], json.dumps(record)))
        old = [r[0] for r in self.db.execute(
            "SELECT id FROM notifications ORDER BY received DESC, id DESC LIMIT -1 OFFSET ?", (HISTORY,))]
        if old:
            self.db.executemany("DELETE FROM notifications WHERE id = ?", [(i,) for i in old])
        return old

    def remove(self, nid: int) -> None:
        self.db.execute("DELETE FROM notifications WHERE id = ?", (nid,))


class Notifyd:
    def __init__(self, state: Path | None = None, cache: Path | None = None, config: Path | None = None):
        self.state = state or paths.state()
        self.images = (cache or paths.cache()) / "notifications"
        self.prefs = settings.Store("desktop", config)
        self.store = Store(self.state)
        self.live = {r["id"]: r for r in self.store.all()}       # id → record (history and transient ones)
        self.next_id = max([self.store.last_id(), *self.live]) + 1 if self.live or self.store.last_id() else 1
        self.badges: dict[str, dict] = {}                        # app key → LauncherEntry properties
        self.badge_owner: dict[str, str] = {}                    # app key → the sender that set it
        self.fdo = Freedesktop(self)
        self.ours = Citron(self)
        self.notifiers_file = self.state / "notifiers.json"
        try:
            self.notifiers = files.read_json(self.notifiers_file, default={}, kind=dict)
        except ValueError:
            self.notifiers = {}

    # -- notifications
    def desktop_prefs(self) -> dict:
        try:
            return self.prefs.peek()
        except settings.SettingsError:
            return {}

    def remember(self, key: str, name: str, icon: str) -> None:
        """The apps that have notified, for Settings › Notifications to list."""
        if key in self.notifiers:
            return
        self.notifiers = {**self.notifiers, key: {"name": name, "icon": icon}}
        try:
            files.atomic_json(self.notifiers_file, self.notifiers)
        except OSError as exc:
            print(f"citronos-notifyd: {self.notifiers_file.name}: {exc}", file=sys.stderr)

    def notify(self, app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout) -> int:
        hints = {k: plain(v) for k, v in (hints or {}).items()}
        desktop_entry = str(hints.get("desktop-entry") or "")
        key = key_of(app_name, desktop_entry)
        owner = owner_of(app_name, desktop_entry)
        self.remember(key, app_name or desktop_entry or key, owner or desktop_entry or app_icon or "")
        nid = replaces_id if replaces_id in self.live else self.new_id()
        prefs = self.desktop_prefs()
        choice = {"allow": True, **focus.app_choice((prefs.get("notifications") or {}).get("apps"), key)}
        if choice.get("allow") is False:
            return nid                                   # not allowed: dropped, as if shown and gone
        urgency = hints.get("urgency", 1)
        urgency = urgency if isinstance(urgency, int) and 0 <= urgency <= 2 else 1
        now = time.time() * 1000
        policy = prefs.get("focus") if isinstance(prefs.get("focus"), dict) else {}
        record = {
            "id": nid, "appName": app_name, "desktopEntry": desktop_entry, "appIcon": app_icon,
            "summary": summary, "body": body, "key": key, "owner": owner, "urgency": urgency,
            "actions": [{"identifier": actions[i], "text": actions[i + 1]} for i in range(0, len(actions) - 1, 2)],
            "image": self.image(nid, hints),
            "expireTimeout": expire_timeout / 1000 if expire_timeout > 0 else 0,
            "resident": hints.get("resident") is True, "transient": hints.get("transient") is True,
            "hints": {"suppress-sound": hints.get("suppress-sound") is True,
                      "category": str(hints.get("category") or "")},
            "received": int(now),
            # Focus decides now, as the notification arrives: kept quiet (no
            # banner, no sound) unless Focus lets this app through.
            "quiet": focus.state(policy, now)["active"] and not focus.allows(policy, key, urgency),
        }
        self.live[nid] = record
        if not record["transient"]:
            for gone in self.store.put(record):
                self.forget(gone)
                self.ours.Removed(gone, EXPIRED)
        self.ours.Added(json.dumps(record))
        return nid

    def new_id(self) -> int:
        nid, self.next_id = self.next_id, self.next_id + 1
        if self.next_id > 0xFFFFFFFF:
            self.next_id = 1
        self.store.set_last_id(nid)
        return nid

    def image(self, nid: int, hints: dict) -> str:
        """The notification's picture as a file the shell can show."""
        raw = hints.get("image-data") or hints.get("image_data") or hints.get("icon_data")
        if isinstance(raw, list) and len(raw) == 7:
            width, height, rowstride, alpha, bits, channels, data = raw
            data = bytes(data)
            if bits == 8 and channels == (4 if alpha else 3) and 0 < width <= 2048 and 0 < height <= 2048 \
                    and len(data) <= MAX_IMAGE and len(data) >= rowstride * (height - 1) + width * channels:
                path = self.images / f"{nid}.png"
                try:
                    files.atomic_write(path, png(width, height, rowstride, bool(alpha), data))
                    return str(path)
                except OSError:
                    return ""
        named = str(hints.get("image-path") or hints.get("image_path") or "")
        if named.startswith("file://"):
            return named[7:]
        if named.startswith("/"):
            return named
        return f"image://icon/{named}" if named else ""

    def forget(self, nid: int) -> None:
        record = self.live.pop(nid, None)
        self.store.remove(nid)
        if record and record.get("image", "").startswith(str(self.images)):
            try:
                os.unlink(record["image"])
            except OSError:
                pass

    def close(self, nid: int, reason: int) -> bool:
        if nid not in self.live:
            return False
        self.forget(nid)
        self.fdo.NotificationClosed(nid, reason)
        self.ours.Removed(nid, reason)
        return True

    def invoke(self, nid: int, action: str) -> None:
        record = self.live.get(nid)
        if not record:
            return
        self.fdo.ActionInvoked(nid, action)
        if not record["resident"]:
            self.close(nid, DISMISSED)

    # -- badges (com.canonical.Unity.LauncherEntry)
    def launcher_update(self, sender: str, uri: str, props: dict) -> None:
        app = uri.removeprefix("application://").removesuffix(".desktop")
        if not app:
            return
        badge = dict(self.badges.get(app, {}))
        for name, kind in (("count", int), ("count-visible", bool), ("progress", float),
                           ("progress-visible", bool), ("urgent", bool)):
            if name in props:
                value = plain(props[name])
                if kind is float and isinstance(value, (int, float)) and not isinstance(value, bool):
                    value = max(0.0, min(1.0, float(value)))
                if isinstance(value, kind) and not (kind is int and isinstance(value, bool)):
                    badge[name] = value
        self.badges[app] = badge
        self.badge_owner[app] = sender
        self.ours.BadgesChanged(json.dumps(self.visible_badges()))

    def sender_left(self, sender: str) -> None:
        gone = [app for app, who in self.badge_owner.items() if who == sender]
        for app in gone:
            self.badges.pop(app, None)
            self.badge_owner.pop(app, None)
        if gone:
            self.ours.BadgesChanged(json.dumps(self.visible_badges()))

    def visible_badges(self) -> dict:
        out = {}
        for app, b in self.badges.items():
            shown = {}
            if b.get("count-visible") and b.get("count", 0) > 0:
                shown["count"] = b["count"]
            if b.get("progress-visible"):
                shown["progress"] = b.get("progress", 0.0)
            if b.get("urgent"):
                shown["urgent"] = True
            if shown:
                out[app] = shown
        return out


class Freedesktop(ServiceInterface):
    """The Desktop Notifications Specification, 1.2."""

    def __init__(self, d: Notifyd):
        super().__init__(FDO[0])
        self.d = d

    @method()
    def GetCapabilities(self) -> "as":  # noqa: F821, F722 - D-Bus signatures
        return ["actions", "body", "icon-static", "persistence"]

    @method()
    def GetServerInformation(self) -> "ssss":  # noqa: F821
        return ["CitronOS", "CitronOS", "4.0", "1.2"]

    @method()
    def Notify(self, app_name: "s", replaces_id: "u", app_icon: "s", summary: "s", body: "s",  # noqa: F821
               actions: "as", hints: "a{sv}", expire_timeout: "i") -> "u":  # noqa: F821, F722
        return self.d.notify(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout)

    @method()
    def CloseNotification(self, nid: "u"):  # noqa: F821
        self.d.close(nid, CLOSED)

    @signal()
    def NotificationClosed(self, nid, reason) -> "uu":  # noqa: F821
        return [nid, reason]

    @signal()
    def ActionInvoked(self, nid, action) -> "us":  # noqa: F821
        return [nid, action]


class Citron(ServiceInterface):
    """What the shell (and Settings) use."""

    def __init__(self, d: Notifyd):
        super().__init__(OURS[0])
        self.d = d

    @method()
    def List(self) -> "s":  # noqa: F821
        return json.dumps(sorted(self.d.live.values(), key=lambda r: (r["received"], r["id"]), reverse=True))

    @method()
    def Dismiss(self, nid: "u"):  # noqa: F821
        self.d.close(nid, DISMISSED)

    @method()
    def DismissApp(self, key: "s"):  # noqa: F821
        for nid in [i for i, r in self.d.live.items() if not key or r["key"] == key]:
            self.d.close(nid, DISMISSED)

    @method()
    def Invoke(self, nid: "u", action: "s"):  # noqa: F821
        self.d.invoke(nid, action)

    @method()
    def Badges(self) -> "s":  # noqa: F821
        return json.dumps(self.d.visible_badges())

    @signal()
    def Added(self, record) -> "s":  # noqa: F821
        return record

    @signal()
    def Removed(self, nid, reason) -> "uu":  # noqa: F821
        return [nid, reason]

    @signal()
    def BadgesChanged(self, badges) -> "s":  # noqa: F821
        return badges


async def serve() -> int:
    d = Notifyd()
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    bus.export(FDO[1], d.fdo)
    bus.export(OURS[1], d.ours)
    for name in (FDO[0], OURS[0]):
        reply = await bus.request_name(name, NameFlag.DO_NOT_QUEUE)
        if reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
            print(f"citronos-notifyd: {name} belongs to another program; leaving it to that", file=sys.stderr)
            return 1

    def incoming(msg: Message):
        if msg.message_type != MessageType.SIGNAL:
            return None
        if msg.interface == LAUNCHER and msg.member == "Update" and len(msg.body) == 2:
            d.launcher_update(msg.sender, str(msg.body[0]), msg.body[1] or {})
        elif msg.interface == DBUS[2] and msg.member == "NameOwnerChanged" and msg.body[2] == "":
            d.sender_left(msg.body[0])
        return None
    bus.add_message_handler(incoming)
    for rule in (f"type='signal',interface='{LAUNCHER}',member='Update'",
                 f"type='signal',sender='{DBUS[0]}',interface='{DBUS[2]}',member='NameOwnerChanged'"):
        await bus.call(Message(destination=DBUS[0], path=DBUS[1], interface=DBUS[2], member="AddMatch",
                               signature="s", body=[rule]))
    await bus.wait_for_disconnect()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(serve()))
