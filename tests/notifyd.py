#!/usr/bin/env python3
"""citronos-notifyd (T-2.6, CS2-024), on a private bus.

An app (a real D-Bus client) sends notifications the standard way; the shell's
side is the bridge QML uses. Checked: a notification reaches the shell and
survives the service (and so the shell) restarting; actions reach the app;
replacing and closing; an app that isn't allowed is dropped but listed for
Settings; Focus marks what it keeps quiet; transient ones aren't kept; an
image becomes a file; the history has a limit; LauncherEntry badges (the API
Electron apps use) come and go with the app; and the Python Focus rules agree
with FocusPolicy.js case by case."""
import datetime
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import threading
import queue
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services/notifyd/notifyd.py"
spec = importlib.util.spec_from_file_location("settingsd_tests", ROOT / "tests/settingsd.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)
sys.path.insert(0, str(ROOT / "apps/lib/python"))
from citronos import focus  # noqa: E402

OURS = ("org.citronos.Notifications1", "/org/citronos/Notifications1")
FDO = "org.freedesktop.Notifications"

APP = r'''
import asyncio, json, sys
from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus
FDO = ("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
def say(o): print(json.dumps(o), flush=True)
def variant(sig, value):
    if sig == "(iiibiiay)":
        value = [*value[:6], bytes(value[6])]
    return Variant(sig, value)
async def main():
    bus = await MessageBus().connect()
    def heard(m):
        if m.message_type == MessageType.SIGNAL and m.interface == FDO[0]:
            say({"signal": m.member, "args": m.body})
    bus.add_message_handler(heard)
    await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                           interface="org.freedesktop.DBus", member="AddMatch", signature="s",
                           body=[f"type='signal',interface='{FDO[0]}'"]))
    say({"ready": True})
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while line := await reader.readline():
        r = json.loads(line)
        if r["do"] == "notify":
            hints = {k: variant(*v) for k, v in r.get("hints", {}).items()}
            reply = await bus.call(Message(destination=FDO[0], path=FDO[1], interface=FDO[0], member="Notify",
                                           signature="susssasa{sv}i",
                                           body=[r.get("app", "Chat"), r.get("replaces", 0), r.get("icon", ""),
                                                 r.get("summary", "Hello"), r.get("body", ""), r.get("actions", []),
                                                 hints, r.get("timeout", -1)]))
            say({"id": r["id"], "result": reply.body})
        elif r["do"] == "close":
            await bus.call(Message(destination=FDO[0], path=FDO[1], interface=FDO[0], member="CloseNotification",
                                   signature="u", body=[r["nid"]]))
            say({"id": r["id"], "result": []})
        elif r["do"] == "launcher":
            await bus.send(Message.new_signal("/org/example/launcher", "com.canonical.Unity.LauncherEntry", "Update",
                                              "sa{sv}", [r["uri"], {k: Variant(*v) for k, v in r["props"].items()}]))
            await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                                   interface="org.freedesktop.DBus", member="GetId"))
            say({"id": r["id"], "result": []})
asyncio.run(main())
'''


class App(harness.Bridge):
    """An app on the bus: sends notifications, hears what happens to them."""

    def __init__(self, env):
        self.p = subprocess.Popen([sys.executable, "-c", APP], env=env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True, bufsize=1)
        self.lines = queue.Queue()
        self.seen = []
        self.next = 1
        threading.Thread(target=self._read, daemon=True).start()
        self.expect(lambda m: m.get("ready"))

    def do(self, what, **args):
        rid, self.next = self.next, self.next + 1
        self.p.stdin.write(json.dumps({"id": rid, "do": what, **args}) + "\n")
        self.p.stdin.flush()
        return self.expect(lambda m: m.get("id") == rid)["result"]

    def notify(self, **args) -> int:
        return self.do("notify", **args)[0]


@unittest.skipUnless(harness.HAVE_BUS, "needs dbus-daemon and dbus-next")
class Service(unittest.TestCase):
    def setUp(self):
        self.bus = harness.PrivateBus({FDO: SERVICE, OURS[0]: SERVICE})
        self.addCleanup(self.bus.close)
        self.shell = self.client()
        self.app = App(self.bus.env)
        self.addCleanup(self.app.close)

    def client(self):
        b = harness.Bridge(self.bus.env, dest=OURS[0], path=OURS[1], signals=("Added", "Removed", "BadgesChanged"))
        self.addCleanup(b.close)
        self.assertEqual(b.expect(lambda m: "ready" in m), {"ready": True})
        return b

    def added(self, client=None):
        msg = (client or self.shell).expect(lambda m: m.get("signal") == "Added")
        return json.loads(msg["args"][0])

    def listed(self, client=None):
        return json.loads((client or self.shell).call("List")["result"][0])

    def restart_service(self):
        fdo = harness.Bridge(self.bus.env, dest="org.freedesktop.DBus", path="/org/freedesktop/DBus", signals=())
        self.addCleanup(fdo.close)
        fdo.expect(lambda m: "ready" in m)
        os.kill(fdo.call("GetConnectionUnixProcessID", OURS[0])["result"][0], signal.SIGKILL)
        self.shell.expect(lambda m: m.get("lost"))

    def test_it_reaches_the_shell_and_outlives_a_restart(self):
        nid = self.app.notify(app="Chat", summary="Lunch?", body="At one", icon="chat",
                              hints={"desktop-entry": ["s", "org.example.Chat"], "urgency": ["y", 1]})
        record = self.added()
        self.assertEqual((record["id"], record["summary"], record["body"], record["key"], record["quiet"]),
                         (nid, "Lunch?", "At one", "org.example.chat", False))
        self.assertEqual(record["desktopEntry"], "org.example.Chat")
        # The shell going away is nothing to it; the service going away loses nothing either.
        self.restart_service()
        later = self.client()
        self.assertEqual([r["id"] for r in self.listed(later)], [nid])
        self.assertGreater(self.app.notify(summary="Next"), nid, "ids aren't reused")

    def test_actions_reach_the_app(self):
        nid = self.app.notify(actions=["default", "Open", "reply", "Reply"])
        self.assertEqual(self.added()["actions"], [{"identifier": "default", "text": "Open"},
                                                   {"identifier": "reply", "text": "Reply"}])
        self.shell.call("Invoke", nid, "reply")
        self.assertEqual(self.app.expect(lambda m: m.get("signal") == "ActionInvoked")["args"], [nid, "reply"])
        self.assertEqual(self.app.expect(lambda m: m.get("signal") == "NotificationClosed")["args"], [nid, 2])
        self.assertEqual(self.shell.expect(lambda m: m.get("signal") == "Removed")["args"], [nid, 2])
        resident = self.app.notify(actions=["default", "Open"], hints={"resident": ["b", True]})
        self.shell.call("Invoke", resident, "default")
        self.app.expect(lambda m: m.get("signal") == "ActionInvoked")
        self.assertEqual([r["id"] for r in self.listed()], [resident], "a resident one stays")

    def test_replaced_and_closed_by_the_app(self):
        nid = self.app.notify(summary="Downloading 10%")
        self.added()
        self.assertEqual(self.app.notify(summary="Downloading 90%", replaces=nid), nid)
        self.assertEqual(self.added()["summary"], "Downloading 90%")
        self.assertEqual(len(self.listed()), 1)
        self.app.do("close", nid=nid)
        self.assertEqual(self.shell.expect(lambda m: m.get("signal") == "Removed")["args"], [nid, 3])
        self.assertEqual(self.listed(), [])

    def test_dismissing_one_app_or_all(self):
        a = self.app.notify(app="Chat", hints={"desktop-entry": ["s", "chat"]})
        self.app.notify(app="Mail", hints={"desktop-entry": ["s", "org.goldengate.Mail"]})
        self.shell.call("DismissApp", "org.goldengate.mail")
        self.assertEqual([r["id"] for r in self.listed()], [a])
        self.shell.call("DismissApp", "")
        self.assertEqual(self.listed(), [])

    def test_an_app_not_allowed_is_dropped_but_listed(self):
        self.assertEqual(self.bus.gg_pref("notifications.apps", json.dumps({"org.example.chat": {"allow": False}})).returncode, 0)
        self.app.notify(app="Chat", hints={"desktop-entry": ["s", "org.example.Chat"]})
        self.app.notify(app="Other")
        self.assertEqual(self.added()["appName"], "Other", "only the allowed one arrives")
        self.assertEqual(len(self.listed()), 1)
        notifiers = json.loads((self.bus.root / "state/golden-gate/notifiers.json").read_text())
        self.assertIn("org.example.chat", notifiers, "Settings can still list it, to allow it again")

    def test_focus_keeps_some_quiet(self):
        policy = {"session": {"on": True, "until": 0}, "allowedApps": {focus.app_key("org.example.vip"): True},
                  "allowCritical": True}
        self.assertEqual(self.bus.gg_pref("focus", json.dumps(policy)).returncode, 0)
        self.app.notify(app="Chat")
        self.assertIs(self.added()["quiet"], True)
        self.app.notify(app="VIP", hints={"desktop-entry": ["s", "org.example.vip"]})
        self.assertIs(self.added()["quiet"], False, "an app Focus allows")
        self.app.notify(app="Alarm", hints={"urgency": ["y", 2]})
        self.assertIs(self.added()["quiet"], False, "critical, and Focus allows critical")

    def test_blueferry_speaks_for_messages(self):
        self.app.notify(app="blueferry", summary="Sam")
        record = self.added()
        self.assertEqual((record["key"], record["owner"]), ("org.goldengate.Messages".lower(), "org.goldengate.Messages"))

    def test_a_transient_one_isnt_kept(self):
        self.app.notify(summary="Volume", hints={"transient": ["b", True]})
        self.added()
        kept = self.app.notify(summary="Kept")
        self.restart_service()
        self.assertEqual([r["id"] for r in self.listed(self.client())], [kept])

    def test_an_image_becomes_a_file(self):
        pixels = [255, 0, 0, 255] * 4
        nid = self.app.notify(hints={"image-data": ["(iiibiiay)", [2, 2, 8, True, 8, 4, pixels]]})
        path = Path(self.added()["image"])
        data = path.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", data[16:24]), (2, 2))
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.shell.call("Dismiss", nid)
        self.shell.expect(lambda m: m.get("signal") == "Removed")
        self.assertFalse(path.exists(), "gone with its notification")
        self.app.notify(hints={"image-path": ["s", "file:///usr/share/pixmaps/x.png"]})
        self.assertEqual(self.added()["image"], "/usr/share/pixmaps/x.png")
        self.app.notify(hints={"image-path": ["s", "mail-unread"]})
        self.assertEqual(self.added()["image"], "image://icon/mail-unread")

    def test_launcher_entry_badges(self):
        """An Electron app's Dock badge and progress (com.canonical.Unity.LauncherEntry)."""
        self.app.do("launcher", uri="application://discord.desktop",
                    props={"count": ["x", 3], "count-visible": ["b", True]})
        badges = json.loads(self.shell.expect(lambda m: m.get("signal") == "BadgesChanged")["args"][0])
        self.assertEqual(badges, {"discord": {"count": 3}})
        self.app.do("launcher", uri="application://discord.desktop",
                    props={"progress": ["d", 0.5], "progress-visible": ["b", True]})
        badges = json.loads(self.shell.expect(lambda m: m.get("signal") == "BadgesChanged")["args"][0])
        self.assertEqual(badges, {"discord": {"count": 3, "progress": 0.5}}, "updates add to what it said")
        self.assertEqual(json.loads(self.shell.call("Badges")["result"][0]), badges)
        self.app.close()                                   # the app quits: its badge goes
        badges = json.loads(self.shell.expect(lambda m: m.get("signal") == "BadgesChanged")["args"][0])
        self.assertEqual(badges, {})


    @unittest.skipUnless(shutil.which("gdbus"), "needs gdbus (glib2)")
    def test_mail_keeps_its_badge_while_closed(self):
        """Mail's helper runs and exits: its badge (SetBadge) stays, even across
        the service restarting, until Mail changes it."""
        def save(uids):
            subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); import helper; "
                            "helper.save_badge('me@example.com', sys.argv[2:])", str(ROOT / "apps/mail"), *uids],
                           env=self.bus.env, check=True, timeout=30)
        save(["1", "2", "3"])
        badges = json.loads(self.shell.expect(lambda m: m.get("signal") == "BadgesChanged")["args"][0])
        self.assertEqual(badges, {"org.goldengate.Mail": {"count": 3}})
        self.assertEqual(json.loads((self.bus.root / "state/golden-gate/mail-badges.json").read_text())["unread"], 3,
                         "and the file a shell without notifyd reads")
        self.restart_service()
        self.assertEqual(json.loads(self.client().call("Badges")["result"][0]), badges)
        save([])
        self.assertEqual(json.loads(self.shell.expect(lambda m: m.get("signal") == "BadgesChanged")["args"][0]), {})


class History(unittest.TestCase):
    def test_the_oldest_go_past_the_limit(self):
        sys.path.insert(0, str(SERVICE.parent))
        try:
            import notifyd
        except ImportError:
            self.skipTest("needs dbus-next")
        with tempfile.TemporaryDirectory() as tmp:
            store = notifyd.Store(Path(tmp))
            gone = []
            for i in range(1, notifyd.HISTORY + 6):
                gone += store.put({"id": i, "received": i})
            self.assertEqual(gone, [1, 2, 3, 4, 5])
            self.assertEqual(len(store.all()), notifyd.HISTORY)
            self.assertEqual((Path(tmp) / "notifications.db").stat().st_mode & 0o777, 0o600)


@unittest.skipUnless(harness.HAVE_BUS and harness.HAVE_QT, "needs dbus-daemon, dbus-next and PySide6")
class ShellClient(unittest.TestCase):
    """The production shell/Notifications.qml as notifyd's client, with the
    real bridge: banners, Notification Center's list, actions, Focus, the
    history across a shell restart, and badges for the Dock."""

    def setUp(self):
        self.bus = harness.PrivateBus({FDO: SERVICE, OURS[0]: SERVICE})
        self.addCleanup(self.bus.close)
        self.app = App(self.bus.env)
        self.addCleanup(self.app.close)
        self.engine = None

    def load(self):
        from PySide6.QtCore import QObject, QUrl
        from PySide6.QtQml import QQmlApplicationEngine
        from PySide6.QtTest import QTest
        if self.engine:
            self.unload()
        self.stand = harness.Stand(self.bus.env)
        self.spawner = harness.Spawner(self.bus.env)
        self.engine = QQmlApplicationEngine()
        self.interceptor = harness.preview.SingletonDirs()
        self.engine.addUrlInterceptor(self.interceptor)
        self.engine.addImportPath(str(ROOT / "tools/preview/qml"))
        self.engine.rootContext().setContextProperty("__preview", self.stand)
        self.engine.rootContext().setContextProperty("__spawner", self.spawner)
        # The production file, in the preview's desktop (as notification-banners.py has it).
        self.engine.setInitialProperties({"targetUrl": QUrl.fromLocalFile(str(ROOT / "shell/Notifications.qml"))})
        self.engine.load(QUrl.fromLocalFile(str(ROOT / "tools/preview/Desktop.qml")))
        self.assertTrue(self.engine.rootObjects())
        self.root = self.engine.rootObjects()[0]
        QTest.qWait(30)
        self.n = None
        stack, seen = [self.root], set()
        while stack and self.n is None:
            o = stack.pop()
            if id(o) in seen:
                continue
            seen.add(id(o))
            if o.objectName() == "notifications":
                self.n = o
            stack.extend(o.children())
        self.assertIsNotNone(self.n, "shell/Notifications.qml didn't load")

    def unload(self):
        for p in self.spawner.live:
            p.kill()
        self.root.deleteLater()
        self.engine.deleteLater()
        harness.APP.processEvents()
        self.engine = None

    def tearDown(self):
        if self.engine:
            self.unload()

    def js(self, expression):
        from PySide6.QtQml import QQmlEngine, QQmlExpression
        e = QQmlExpression(QQmlEngine.contextForObject(self.n), self.n, expression)
        v = e.evaluate()[0]
        self.assertFalse(e.hasError(), e.error().toString())
        return v.toVariant() if hasattr(v, "toVariant") else v

    def wait(self, expression, timeout=10):
        from PySide6.QtTest import QTest
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.js(expression):
                return
            QTest.qWait(20)
        self.fail(f"timed out waiting for {expression}")

    def test_banners_and_notification_center_come_from_notifyd(self):
        self.load()
        self.wait("viaService")
        self.assertTrue(self.js("fallback.item === null"), "the shell isn't a second server")
        nid = self.app.notify(app="Calendar", summary="Design review", body="Today at 10:30",
                              hints={"desktop-entry": ["s", "org.goldengate.Calendar"]})
        self.wait("banners.length === 1 && list.length === 1")
        self.assertEqual(self.js("banners[0].summary"), "Design review")
        self.assertEqual(self.js(f"timeLabel(list[0])"), "now")
        self.js("list[0].dismiss()")
        self.wait("list.length === 0 && banners.length === 0")
        self.assertEqual(self.app.expect(lambda m: m.get("signal") == "NotificationClosed")["args"], [nid, 2])

    def test_opening_one_runs_its_action(self):
        self.load()
        self.wait("viaService")
        nid = self.app.notify(actions=["default", "Show", "later", "Later"])
        self.wait("list.length === 1")
        self.assertEqual(self.js("list[0].actions.map((a) => a.text)"), ["Show", "Later"])
        self.js("open(list[0])")
        self.wait("list.length === 0")              # (Qt's event loop sends the call to the bridge)
        self.assertEqual(self.app.expect(lambda m: m.get("signal") == "ActionInvoked")["args"], [nid, "default"])

    def test_focus_keeps_it_out_of_the_banners(self):
        self.bus.gg_pref("focus", json.dumps({"session": {"on": True, "until": 0}}))
        self.load()
        self.wait("viaService")
        self.app.notify(summary="Quietly")
        self.wait("list.length === 1")
        from PySide6.QtTest import QTest
        QTest.qWait(150)
        self.assertEqual(self.js("banners.length"), 0, "kept in Notification Center, no banner")

    def test_the_history_outlives_the_shell(self):
        self.load()
        self.wait("viaService")
        self.app.notify(summary="One")
        self.app.notify(summary="Two")
        self.wait("list.length === 2")
        self.unload()                                  # the shell quits (or crashes)
        self.load()
        self.wait("viaService && list.length === 2")
        self.assertEqual(self.js("list.map((n) => n.summary)"), ["Two", "One"])
        self.assertEqual(self.js("banners.length"), 0, "old ones don't come back as banners")

    def test_apps_badges_and_progress_reach_the_dock(self):
        self.load()
        self.wait("viaService")
        self.app.do("launcher", uri="application://discord.desktop",
                    props={"count": ["x", 3], "count-visible": ["b", True],
                           "progress": ["d", 0.4], "progress-visible": ["b", True]})
        self.wait('countFor("discord", "") === 3 && progressFor("com.discordapp.discord", "discord") === 0.4')
        self.app.close()
        self.wait('countFor("discord", "") === 0 && progressFor("discord", "") === -1')

    def test_without_notifyd_the_shell_is_the_server(self):
        self.bus.env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/nonexistent/bus"
        self.load()
        self.wait("fallback.item !== null", timeout=15)
        self.assertFalse(self.js("viaService"))


@unittest.skipUnless(shutil.which("node"), "needs node")
class FocusRules(unittest.TestCase):
    """citronos.focus and apps/lib/FocusPolicy.js, case by case."""

    def test_the_same_answers(self):
        tz = "Europe/Berlin"                 # with a DST change in the cases
        before = os.environ.get("TZ")
        os.environ["TZ"] = tz
        time.tzset()

        def restore():
            if before is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = before
            time.tzset()
        self.addCleanup(restore)
        ms = lambda *a: int(datetime.datetime(*a).timestamp() * 1000)
        schedule = {"enabled": True, "days": [1, 2, 3, 4, 5], "start": 22 * 60, "end": 7 * 60}
        cases = []
        for now in (ms(2026, 10, 26, 23, 0), ms(2026, 10, 27, 6, 59), ms(2026, 10, 27, 7, 0),
                    ms(2026, 10, 24, 23, 30), ms(2026, 10, 25, 1, 30), ms(2026, 3, 29, 2, 30), ms(2026, 10, 31, 6, 0)):
            for policy in ({}, {"schedule": schedule}, {"dnd": True}, {"session": {"on": True, "until": 0}},
                           {"session": {"on": True, "until": now - 1}}, {"session": {"on": True, "until": now + 60000}},
                           {"session": {"on": False, "pauseUntil": now + 1}, "schedule": schedule},
                           {"session": {"on": False, "pauseUntil": 0}, "schedule": schedule},
                           {"schedule": {**schedule, "start": 60, "end": 60}}):
                cases.append({"fn": "state", "policy": policy, "now": now})
        allowed = {"allowedApps": {focus.app_key("mail"): True, focus.app_key("org.example.Chat"): True},
                   "allowCritical": True}
        for key in ("mail", "Mail", "org.goldengate.Mail", "org.example.Chat", "org.example.chat", "other", "a b/ü"):
            for urgency in (0, 1, 2):
                cases.append({"fn": "allows", "policy": allowed, "key": key, "urgency": urgency})
                cases.append({"fn": "allows", "policy": {"allowedApps": allowed["allowedApps"]}, "key": key,
                              "urgency": urgency})
            cases.append({"fn": "appKey", "key": key})
            choices = {"org.goldengate.mail": {"allow": False}, "clock": {"banners": False},
                       "org.example.chat": {"sound": False}}
            cases.append({"fn": "appChoice", "choices": choices, "key": key})
        for key in ("clock", "org.goldengate.clock"):
            cases.append({"fn": "appChoice", "choices": {"clock": {"banners": False}}, "key": key})

        source = (ROOT / "apps/lib/FocusPolicy.js").read_text().replace(".pragma library", "")
        script = source + """
const cases = JSON.parse(require("fs").readFileSync(0, "utf8"))
console.log(JSON.stringify(cases.map((c) => c.fn === "state" ? state(c.policy, c.now)
    : c.fn === "allows" ? allows(c.policy, c.key, c.urgency)
    : c.fn === "appKey" ? appKey(c.key) : appChoice(c.choices, c.key))))
"""
        js = json.loads(subprocess.run(["node", "-e", script], input=json.dumps(cases), capture_output=True,
                                       text=True, check=True, env={**os.environ, "TZ": tz}).stdout)
        for case, expected in zip(cases, js):
            got = (focus.state(case["policy"], case["now"]) if case["fn"] == "state"
                   else focus.allows(case["policy"], case["key"], case["urgency"]) if case["fn"] == "allows"
                   else focus.app_key(case["key"]) if case["fn"] == "appKey"
                   else focus.app_choice(case["choices"], case["key"]))
            with self.subTest(case=case):
                self.assertEqual(json.loads(json.dumps(got)), expected)
        self.assertGreater(len(cases), 100)


class Packaging(unittest.TestCase):
    def test_unit_activation_and_install(self):
        unit = (ROOT / "distro/systemd/user/citronos-notifyd.service").read_text()
        for line in ("Type=dbus", "BusName=org.citronos.Notifications1", "ExecStart=/usr/bin/env gg-notifyd",
                     "PartOf=citronos-session.target"):
            self.assertIn(line, unit)
        self.assertIn("citronos-notifyd.service", (ROOT / "distro/systemd/user/citronos-session.target").read_text())
        for name in (FDO, OURS[0]):
            activation = (ROOT / f"distro/dbus/{name}.service").read_text()
            self.assertIn(f"Name={name}", activation)
            self.assertIn("SystemdService=citronos-notifyd.service", activation)
        install = (ROOT / "scripts/install.sh").read_text()
        self.assertIn("services/notifyd/notifyd.py", install)
        self.assertIn('"$BIN/gg-notifyd"', install)
        self.assertRegex((ROOT / "scripts/stage.sh").read_text(), r"\ngg-notifyd +python3 +\$LIB/notifyd.py\n")


if __name__ == "__main__":
    unittest.main()
