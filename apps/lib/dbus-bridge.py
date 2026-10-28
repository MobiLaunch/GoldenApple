#!/usr/bin/env python3
"""gg-dbus-bridge: one D-Bus object for QML, as JSON lines (T-2.5).

Quickshell has no general D-Bus type yet, so DBusObject.qml runs this for as
long as it lives and talks to it over stdin and stdout:

    dbus-bridge.py --dest org.citronos.Settings1 --path /org/citronos/Settings1 \\
                   --interface org.citronos.Settings1 --signal Changed

    → {"ready": true}                     the object answered (started if need be)
    ← {"id": 1, "call": "Get", "args": ["desktop", "dock.size"]}
    → {"id": 1, "ok": true, "result": ["54"]}
    → {"id": 2, "ok": false, "error": "org.citronos.Settings1.Error.Invalid",
       "message": "dock.size should be a number."}
    → {"signal": "Changed", "args": ["desktop", "dock.size", "64"]}
    → {"ready": false, "lost": true}      the service went away; {"ready": true}
                                          when it's back (it's started again)

Arguments are typed from the object's own introspection, so only the method's
name and JSON values cross. A signal is written before the reply to the call
that caused it. The bridge exits when stdin closes (its QML item went away) or
its parent dies; if the object can't be reached at the start it says why
({"ready": false, "error": …}) and exits 1.
"""
import argparse
import asyncio
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "python"))
from citronos import proc  # noqa: E402

try:
    from dbus_next import BusType, Message, MessageType, Variant
    from dbus_next.aio import MessageBus
except ImportError:                         # pragma: no cover - the image has it
    MessageBus = None

DBUS = ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus")
RETRY = (1, 5, 15, 60)                      # seconds between attempts to start it again


def say(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def plain(value):
    """A D-Bus value as JSON can carry it."""
    if isinstance(value, Variant):
        return plain(value.value)
    if isinstance(value, (list, tuple)):
        return [plain(v) for v in value]
    if isinstance(value, dict):
        return {str(k): plain(v) for k, v in value.items()}
    if isinstance(value, bytes):
        return list(value)
    return value


class Bridge:
    def __init__(self, args):
        self.args = args
        self.bus = None
        self.methods: dict[str, str] = {}
        self.ready = False
        self.revive: asyncio.Task | None = None

    async def reach(self) -> None:
        """Introspects the object, which starts its service if it's activatable."""
        node = await self.bus.introspect(self.args.dest, self.args.path, timeout=10)
        iface = next((i for i in node.interfaces if i.name == self.args.interface), None)
        if iface is None:
            raise LookupError(f"{self.args.path} has no {self.args.interface} interface")
        self.methods = {m.name: "".join(a.signature for a in m.in_args) for m in iface.methods}

    def set_ready(self, ready: bool, **extra) -> None:
        if ready != self.ready:
            self.ready = ready
            say({"ready": ready, **extra})

    async def match(self, rule: str) -> None:
        await self.bus.call(Message(destination=DBUS[0], path=DBUS[1], interface=DBUS[2],
                                    member="AddMatch", signature="s", body=[rule]))

    def incoming(self, msg: Message):
        if msg.message_type != MessageType.SIGNAL:
            return None
        a = self.args
        if msg.interface == a.interface and msg.path == a.path and msg.member in a.signal:
            say({"signal": msg.member, "args": plain(msg.body)})
        elif msg.member == "NameOwnerChanged" and msg.interface == DBUS[2] and msg.body[0] == a.dest:
            if msg.body[2]:
                self.set_ready(True)
            else:
                self.set_ready(False, lost=True)
                if self.revive is None or self.revive.done():
                    self.revive = asyncio.ensure_future(self.start_again())
        return None

    async def start_again(self) -> None:
        """A service that stopped is started again (by activation), more
        slowly each time it can't be."""
        for delay in (*RETRY, *([RETRY[-1]] * 1000)):
            await asyncio.sleep(delay)
            if self.ready:
                return
            try:
                await self.reach()
                self.set_ready(True)
                return
            except Exception:  # noqa: BLE001 - try again later
                continue

    async def call(self, request: dict) -> None:
        rid = request.get("id")
        name = request.get("call", "")
        sig = self.methods.get(name)
        if sig is None:
            say({"id": rid, "ok": False, "error": "org.freedesktop.DBus.Error.UnknownMethod",
                 "message": f"{self.args.interface} has no {name}"})
            return
        try:
            reply = await self.bus.call(Message(destination=self.args.dest, path=self.args.path,
                                                interface=self.args.interface, member=name,
                                                signature=sig, body=list(request.get("args") or [])))
        except Exception as exc:  # noqa: BLE001 - wrong arguments, a lost bus
            say({"id": rid, "ok": False, "error": "org.citronos.Bridge.Error.Failed", "message": str(exc)})
            return
        if reply.message_type == MessageType.ERROR:
            # The service's own words; never a traceback (dbus-next appends one).
            message = reply.body[0] if reply.body and isinstance(reply.body[0], str) else reply.error_name
            message = message.split("\n", 1)[0]
            say({"id": rid, "ok": False, "error": reply.error_name, "message": message})
        else:
            say({"id": rid, "ok": True, "result": plain(reply.body)})

    async def run(self) -> int:
        a = self.args
        if MessageBus is None:
            say({"ready": False, "error": "python-dbus-next isn't installed"})
            return 1
        try:
            self.bus = await MessageBus(bus_type=BusType.SYSTEM if a.bus == "system" else BusType.SESSION).connect()
            self.bus.add_message_handler(self.incoming)
            for member in a.signal:
                await self.match(f"type='signal',sender='{a.dest}',interface='{a.interface}',"
                                 f"member='{member}',path='{a.path}'")
            await self.match(f"type='signal',sender='{DBUS[0]}',interface='{DBUS[2]}',"
                             f"member='NameOwnerChanged',arg0='{a.dest}'")
            await self.reach()
        except Exception as exc:  # noqa: BLE001 - no bus, no service: say so
            say({"ready": False, "error": str(exc) or type(exc).__name__})
            return 1
        self.set_ready(True)

        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader(limit=4 * 1024 * 1024)
        await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
        pending = set()
        while line := await reader.readline():
            try:
                request = json.loads(line)
                if not isinstance(request, dict):
                    raise ValueError
            except ValueError:
                say({"ok": False, "error": "org.citronos.Bridge.Error.BadRequest", "message": "not a JSON object"})
                continue
            task = asyncio.ensure_future(self.call(request))
            pending.add(task)
            task.add_done_callback(pending.discard)
        if pending:
            await asyncio.wait(pending, timeout=5)
        self.bus.disconnect()
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bus", choices=("session", "system"), default="session")
    parser.add_argument("--dest", required=True)
    parser.add_argument("--path", required=True)
    parser.add_argument("--interface")
    parser.add_argument("--signal", action="append", default=[])
    args = parser.parse_args()
    args.interface = args.interface or args.dest
    proc.die_with_parent()
    return asyncio.run(Bridge(args).run())


if __name__ == "__main__":
    raise SystemExit(main())
