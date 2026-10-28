#!/usr/bin/env python3
"""citronos-settingsd: CitronOS's preferences on the session bus (T-2.5).

    org.citronos.Settings1 at /org/citronos/Settings1, values as JSON text:
      Get(domain, key) → value          the saved value, else the schema's default
      GetAll(domain) → preferences      what's saved (clients know the defaults)
      Set(domain, key, value)           checked against the schema, then saved
      Changed(domain, key, value)       for every change, whoever made it
      Restored(domain, message)         a damaged file was put back from its copy

The store is citronos.settings (one file per domain, its type for every key,
the last good copy as .bak), so the service, gg-pref and anything else that
writes take turns under the same lock and none loses another's change. A
change made outside the service (gg-pref, a text editor) is seen in the
folder and sent as Changed too; a file damaged that way is left until the
next change or login, which put it back.

Started by D-Bus activation (org.citronos.Settings1.service) as the systemd
user unit citronos-settingsd.service.
"""
import asyncio
import ctypes
import json
import os
from pathlib import Path
import shutil
import struct
import sys

HERE = Path(__file__).resolve()
# The citronos package: in the repository, a per-user install, and the shared UI.
for candidate in (HERE.parents[2] / "apps/lib/python", HERE.parents[1] / "apps/lib/python",
                  Path("/usr/share/golden-gate/ui/python")):
    if (candidate / "citronos").is_dir():
        sys.path.insert(0, str(candidate))
        break
from citronos import paths, settings  # noqa: E402

from dbus_next import BusType, RequestNameReply  # noqa: E402
from dbus_next.aio import MessageBus  # noqa: E402
from dbus_next.errors import DBusError  # noqa: E402
from dbus_next.service import ServiceInterface, method, signal  # noqa: E402

NAME = "org.citronos.Settings1"
PATH = "/org/citronos/Settings1"
ERRORS = {"invalid": NAME + ".Error.Invalid", "unknown": NAME + ".Error.Unknown", "damaged": NAME + ".Error.Damaged"}
IN_CLOSE_WRITE, IN_MOVED_TO = 0x8, 0x80
_MISSING = object()


def same(a, b) -> bool:
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def changes(old: dict, new: dict, prefix: str = ""):
    """(dotted key, new value) for each difference, down to the keys that
    aren't objects (an object that's new or gone counts as an empty one); a
    key that went away is None, its default."""
    for key in sorted(set(old) | set(new)):
        a, b = old.get(key, _MISSING), new.get(key, _MISSING)
        if a is not _MISSING and b is not _MISSING and same(a, b):
            continue
        if isinstance(a, dict) and isinstance(b, dict) or (a is _MISSING and isinstance(b, dict)) \
                or (b is _MISSING and isinstance(a, dict)):
            yield from changes(a if isinstance(a, dict) else {}, b if isinstance(b, dict) else {}, f"{prefix}{key}.")
        else:
            yield prefix + key, (None if b is _MISSING else b)


async def tell(notice: str) -> None:
    child = await asyncio.create_subprocess_exec(
        "notify-send", "-a", "CitronOS", "-i", "dialog-information", "Preferences restored", notice,
        stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
    await child.wait()


class Settings(ServiceInterface):
    def __init__(self, folder: Path | None = None):
        super().__init__(NAME)
        self.stores = {d: settings.Store(d, folder) for d in settings.SCHEMA if not d.startswith("_")}
        self.seen: dict[str, dict] = {}
        for domain, store in self.stores.items():
            try:
                self.notify(domain, store.check_file())
            except settings.SettingsError as exc:
                print(f"citronos-settingsd: {exc}", file=sys.stderr)
            try:
                self.seen[domain] = store.peek()
            except settings.SettingsError:
                self.seen[domain] = {}

    def store(self, domain: str) -> settings.Store:
        if domain not in self.stores:
            raise DBusError(ERRORS["unknown"], f"There are no {domain} preferences.")
        return self.stores[domain]

    def refresh(self, domain: str) -> None:
        """Reads the domain's file and sends Changed for what's different."""
        try:
            now = self.stores[domain].peek()
        except settings.SettingsError:
            return                  # damaged: the last good values stand until it's put back
        before, self.seen[domain] = self.seen[domain], now
        for key, value in changes(before, now):
            self.Changed(domain, key, json.dumps(value))

    def notify(self, domain: str, notice: str) -> None:
        if not notice:
            return
        self.Restored(domain, notice)
        if shutil.which("notify-send"):
            asyncio.ensure_future(tell(notice))

    @method()
    def Get(self, domain: "s", key: "s") -> "s":  # noqa: F821 - D-Bus signatures
        try:
            return json.dumps(self.store(domain).get(key))
        except settings.SettingsError as exc:
            raise DBusError(ERRORS[exc.code], str(exc)) from None

    @method()
    def GetAll(self, domain: "s") -> "s":  # noqa: F821
        self.store(domain)
        self.refresh(domain)
        return json.dumps(self.seen[domain])

    @method()
    def Set(self, domain: "s", key: "s", value: "s"):  # noqa: F821
        store = self.store(domain)
        try:
            parsed = json.loads(value)
        except ValueError:
            raise DBusError(ERRORS["invalid"], f"The value for {key} isn't JSON.") from None
        store.notice = ""
        try:
            store.set(key, parsed)
        except settings.SettingsError as exc:
            raise DBusError(ERRORS[exc.code], str(exc)) from None
        except OSError as exc:
            raise DBusError(NAME + ".Error.Failed", f"{store.file.name} can't be saved ({exc.strerror or exc}).") from None
        # Changed goes out before the reply, so a client that changed a key
        # hears its own change first.
        self.refresh(domain)
        self.notify(domain, store.notice)

    @signal()
    def Changed(self, domain, key, value) -> "sss":  # noqa: F821
        return [domain, key, value]

    @signal()
    def Restored(self, domain, message) -> "ss":  # noqa: F821
        return [domain, message]


def watch(folder: Path, on_change) -> None:
    """Calls on_change(filename) when a file in folder is written or moved
    in (inotify); every two seconds by modification time without it."""
    loop = asyncio.get_running_loop()
    libc = ctypes.CDLL(None, use_errno=True)
    fd = -1
    try:
        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if fd < 0 or libc.inotify_add_watch(fd, str(folder).encode(), IN_CLOSE_WRITE | IN_MOVED_TO) < 0:
            raise OSError(ctypes.get_errno(), "inotify")
    except (OSError, AttributeError):
        if fd >= 0:
            os.close(fd)

        async def poll():
            stamps = {}
            while True:
                for f in folder.glob("*.json"):
                    try:
                        stamp = f.stat().st_mtime_ns
                    except OSError:
                        continue
                    if stamps.get(f.name, stamp) != stamp:
                        on_change(f.name)
                    stamps[f.name] = stamp
                await asyncio.sleep(2)
        asyncio.ensure_future(poll())
        return

    def readable():
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return
        offset = 0
        while offset + 16 <= len(data):
            _wd, _mask, _cookie, length = struct.unpack_from("iIII", data, offset)
            name = data[offset + 16:offset + 16 + length].split(b"\0", 1)[0].decode(errors="replace")
            offset += 16 + length
            on_change(name)
    loop.add_reader(fd, readable)


async def serve(folder: Path | None = None) -> int:
    folder = Path(folder) if folder else paths.config()
    folder.mkdir(parents=True, exist_ok=True)
    service = Settings(folder)
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    bus.export(PATH, service)
    if await bus.request_name(NAME) not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
        print("citronos-settingsd: already running", file=sys.stderr)
        return 0
    files = {store.file.name: domain for domain, store in service.stores.items()}
    watch(folder, lambda name: name in files and service.refresh(files[name]))
    try:
        await bus.wait_for_disconnect()
    except (EOFError, OSError):         # the session's bus went away: the session ended
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(serve()))
