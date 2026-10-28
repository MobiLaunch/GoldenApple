#!/usr/bin/env python3
"""citronos-settingsd and gg-dbus-bridge (T-2.5, CS2-023), on a private bus.

The service is started by D-Bus activation as it would be in a session; the
clients are the bridge QML uses, run for real. Checked: a change is saved
and every client hears it (the one that made it before its reply); a wrong
value is refused with the reason; changes made elsewhere (gg-pref, an editor)
are heard; a damaged file is put back and said; writers through the service
and gg-pref at once lose nothing; a stopped service is started again; and
the round trip is measured against gg-pref's."""
import json
import os
from pathlib import Path
import queue
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "apps/lib/dbus-bridge.py"
SERVICE = ROOT / "services/settingsd/settingsd.py"
PREF = ROOT / "apps/setup/pref-helper.py"
SETTINGS = ("org.citronos.Settings1", "/org/citronos/Settings1")
HAVE_BUS = shutil.which("dbus-daemon") is not None
try:
    import dbus_next  # noqa: F401
except ImportError:
    HAVE_BUS = False


class PrivateBus:
    """A session bus of our own, with citronos-settingsd activatable on it
    and a notify-send that writes down what it was asked to show."""

    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.sock = Path(tempfile.mkdtemp(prefix="ggbus.", dir="/tmp"))   # short: a socket path has a limit
        self.config = self.root / "config"
        (self.root / "services").mkdir()
        (self.root / "bin").mkdir()
        notify = self.root / "bin/notify-send"
        notify.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> {self.root}/notified\n")
        notify.chmod(0o755)
        (self.root / "services/org.citronos.Settings1.service").write_text(
            f"[D-BUS Service]\nName={SETTINGS[0]}\nExec={sys.executable} {SERVICE}\n")
        (self.root / "bus.conf").write_text(
            f"<busconfig><type>session</type><listen>unix:dir={self.sock}</listen>"
            f"<servicedir>{self.root}/services</servicedir><policy context='default'>"
            "<allow send_destination='*' eavesdrop='true'/><allow eavesdrop='true'/><allow own='*'/>"
            "</policy></busconfig>")
        self.env = {**os.environ, "XDG_CONFIG_HOME": str(self.config),
                    "PATH": f"{self.root}/bin:{os.environ['PATH']}"}
        out = subprocess.run(["dbus-daemon", f"--config-file={self.root}/bus.conf", "--print-address=1",
                              "--print-pid=1", "--fork"], env=self.env, capture_output=True, text=True, check=True)
        address, pid = out.stdout.split()[:2]
        self.pid = int(pid)
        self.env["DBUS_SESSION_BUS_ADDRESS"] = address
        self.file = self.config / "golden-gate/desktop.json"

    def notified(self) -> str:
        try:
            return (self.root / "notified").read_text()
        except FileNotFoundError:
            return ""

    def gg_pref(self, *args):
        return subprocess.run([sys.executable, str(PREF), *args], env=self.env, capture_output=True, text=True)

    def close(self):
        try:
            os.kill(self.pid, signal.SIGTERM)       # the service leaves with its bus
        except ProcessLookupError:
            pass
        time.sleep(0.1)
        shutil.rmtree(self.sock, ignore_errors=True)
        self.tmp.cleanup()


class Bridge:
    """dbus-bridge.py as DBusObject.qml runs it."""

    def __init__(self, env, dest=SETTINGS[0], path=SETTINGS[1], signals=("Changed", "Restored"), interface=None):
        args = [sys.executable, str(BRIDGE), "--dest", dest, "--path", path]
        args += ["--interface", interface] if interface else []
        for s in signals:
            args += ["--signal", s]
        self.p = subprocess.Popen(args, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.lines: queue.Queue = queue.Queue()
        self.seen: list[dict] = []
        self.next = 1
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.p.stdout:
            self.lines.put(json.loads(line))
        self.lines.put(None)

    def expect(self, pred, timeout=10):
        deadline = time.monotonic() + timeout
        for msg in self.seen:
            if pred(msg):
                self.seen.remove(msg)
                return msg
        while (left := deadline - time.monotonic()) > 0:
            try:
                msg = self.lines.get(timeout=left)
            except queue.Empty:
                break
            if msg is None:
                raise AssertionError("the bridge exited")
            self.seen.append(msg)
            if pred(msg):
                self.seen.remove(msg)
                return msg
        raise AssertionError(f"nothing matched; seen {self.seen}")

    def send(self, method, *args) -> int:
        rid, self.next = self.next, self.next + 1
        self.p.stdin.write(json.dumps({"id": rid, "call": method, "args": list(args)}) + "\n")
        self.p.stdin.flush()
        return rid

    def call(self, method, *args, timeout=10):
        rid = self.send(method, *args)
        return self.expect(lambda m: m.get("id") == rid, timeout)

    def changed(self, key, timeout=10):
        msg = self.expect(lambda m: m.get("signal") == "Changed" and m["args"][1] == key, timeout)
        return json.loads(msg["args"][2])

    def close(self):
        if self.p.poll() is None:
            self.p.stdin.close()
            try:
                self.p.wait(5)
            except subprocess.TimeoutExpired:
                self.p.kill()
                self.p.wait()
        self.p.stdout.close()


@unittest.skipUnless(HAVE_BUS, "needs dbus-daemon and dbus-next")
class Service(unittest.TestCase):
    def setUp(self):
        self.bus = PrivateBus()
        self.addCleanup(self.bus.close)

    def bridge(self, **kw):
        b = Bridge(self.bus.env, **kw)
        self.addCleanup(b.close)
        self.assertEqual(b.expect(lambda m: "ready" in m), {"ready": True})
        return b

    def test_started_on_first_use(self):
        b = self.bridge()
        self.assertEqual(b.call("GetAll", "desktop"), {"id": 1, "ok": True, "result": ["{}"]})
        self.assertEqual(json.loads(b.call("Get", "desktop", "dock.size")["result"][0]), 54)
        self.assertFalse(b.call("GetAll", "nonsense")["ok"])

    def test_a_change_is_saved_and_everyone_hears_it(self):
        a, b = self.bridge(), self.bridge()
        rid = a.send("Set", "desktop", "dock.pinned", json.dumps(["org.goldengate.Files"]))
        heard = a.expect(lambda m: m.get("signal") == "Changed" or m.get("id") == rid)
        self.assertIn("signal", heard, "its own change is heard before the reply")
        self.assertEqual(a.expect(lambda m: m.get("id") == rid)["ok"], True)
        self.assertEqual(b.changed("dock.pinned"), ["org.goldengate.Files"])
        self.assertEqual(json.loads(self.bus.file.read_text()), {"dock": {"pinned": ["org.goldengate.Files"]}})

    def test_a_wrong_value_is_refused_with_its_reason(self):
        b = self.bridge()
        r = b.call("Set", "desktop", "dock.size", '"huge"')
        self.assertEqual(r["error"], "org.citronos.Settings1.Error.Invalid")
        self.assertEqual(r["message"], "dock.size should be a number.")
        self.assertEqual(b.call("Set", "desktop", "dock.colour", '"red"')["error"], "org.citronos.Settings1.Error.Unknown")
        self.assertEqual(b.call("Set", "desktop", "dock.size", "{oops")["error"], "org.citronos.Settings1.Error.Invalid")
        self.assertEqual(b.call("Set", "desktop")["error"], "org.citronos.Bridge.Error.Failed")
        self.assertEqual(b.call("Nope")["error"], "org.freedesktop.DBus.Error.UnknownMethod")
        self.assertFalse(self.bus.file.exists())

    def test_changes_made_elsewhere_are_heard(self):
        b = self.bridge()
        self.assertEqual(self.bus.gg_pref("menuBar.items.wifi", "false").returncode, 0)
        self.assertIs(b.changed("menuBar.items.wifi"), False)
        # An editor saving the file whole: each difference, as deep as it goes.
        saved = json.loads(self.bus.file.read_text())
        saved["menuBar"]["items"]["battery"] = False
        saved["glass"] = "tinted"
        del saved["menuBar"]["items"]["wifi"]
        self.bus.file.write_text(json.dumps(saved))
        self.assertIs(b.changed("menuBar.items.battery"), False)
        self.assertEqual(b.changed("glass"), "tinted")
        self.assertIsNone(b.changed("menuBar.items.wifi"), "gone: its default again")

    def test_a_damaged_file_is_put_back_and_said(self):
        b = self.bridge()
        b.call("Set", "desktop", "wallpaper", '"/home/me/beach.jpg"')
        b.call("Set", "desktop", "dock.size", "70")
        b.seen.clear()                                               # those changes' own signals
        self.bus.file.write_text('{"dock": {"si')                    # damaged by hand
        time.sleep(0.3)
        self.assertFalse([m for m in b.seen if m.get("signal") == "Changed"], "a damaged file changes nothing")
        self.assertEqual(json.loads(b.call("GetAll", "desktop")["result"][0])["wallpaper"], "/home/me/beach.jpg")
        self.assertTrue(b.call("Set", "desktop", "dock.size", "72")["ok"])
        restored = b.expect(lambda m: m.get("signal") == "Restored")
        self.assertIn("put back", restored["args"][1])
        saved = json.loads(self.bus.file.read_text())
        self.assertEqual((saved["wallpaper"], saved["dock"]["size"]), ("/home/me/beach.jpg", 72))
        for _ in range(50):
            if "Preferences restored" in self.bus.notified():
                break
            time.sleep(0.05)
        self.assertIn("Preferences restored", self.bus.notified())

    def test_no_change_is_lost(self):
        # Two clients of the service and gg-pref, all at once, each with its own keys.
        a, b = self.bridge(), self.bridge()
        for i in range(12):
            a.send("Set", "desktop", f"menuBar.items.a{i}", "true")
            b.send("Set", "desktop", f"menuBar.items.b{i}", "true")
        writers = [subprocess.Popen([sys.executable, str(PREF), f"menuBar.items.g{i}", "true"], env=self.bus.env)
                   for i in range(6)]
        for w in writers:
            self.assertEqual(w.wait(30), 0)
        for client in (a, b):
            for _ in range(12):
                self.assertTrue(client.expect(lambda m: "id" in m)["ok"])
        items = json.loads(self.bus.file.read_text())["menuBar"]["items"]
        self.assertEqual(len(items), 30, sorted(items))

    def test_a_stopped_service_is_started_again(self):
        b = self.bridge()
        bus = self.bridge(dest="org.freedesktop.DBus", path="/org/freedesktop/DBus", signals=())
        pid = bus.call("GetConnectionUnixProcessID", SETTINGS[0])["result"][0]
        os.kill(pid, signal.SIGKILL)
        self.assertEqual(b.expect(lambda m: "ready" in m), {"ready": False, "lost": True})
        self.assertEqual(b.expect(lambda m: "ready" in m, timeout=15), {"ready": True})
        self.assertTrue(b.call("Set", "desktop", "glass", '"tinted"')["ok"])
        self.assertEqual(b.changed("glass"), "tinted", "and its signals still arrive")

    def test_the_round_trip_is_quick(self):
        """The plan's condition for the bridge (05 §Why Python and D-Bus):
        measured, and well under gg-pref's start-a-process-per-write."""
        b = self.bridge()
        times = []
        for i in range(60):
            started = time.perf_counter()
            self.assertTrue(b.call("Set", "desktop", "dock.size", str(40 + i % 50))["ok"])
            times.append((time.perf_counter() - started) * 1000)
        pref = []
        for i in range(8):
            started = time.perf_counter()
            self.assertEqual(self.bus.gg_pref("dock.size", str(40 + i)).returncode, 0)
            pref.append((time.perf_counter() - started) * 1000)
        bridge_median, pref_median = statistics.median(times), statistics.median(pref)
        print(f"\n  Set through the bridge: median {bridge_median:.1f} ms, "
              f"p90 {statistics.quantiles(times, n=10)[-1]:.1f} ms; gg-pref: median {pref_median:.1f} ms",
              file=sys.stderr)
        self.assertLess(bridge_median, 25)
        self.assertLess(bridge_median, pref_median)


class BridgeAlone(unittest.TestCase):
    def test_without_a_bus_it_says_so(self):
        env = {**os.environ, "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/bus"}
        p = subprocess.run([sys.executable, str(BRIDGE), "--dest", SETTINGS[0], "--path", SETTINGS[1]],
                           env=env, capture_output=True, text=True, timeout=20, stdin=subprocess.DEVNULL)
        self.assertEqual(p.returncode, 1)
        msg = json.loads(p.stdout)
        self.assertIs(msg["ready"], False)
        self.assertTrue(msg["error"])

    @unittest.skipUnless(HAVE_BUS, "needs dbus-daemon and dbus-next")
    def test_it_leaves_with_its_item(self):
        bus = PrivateBus()
        self.addCleanup(bus.close)
        b = Bridge(bus.env)
        b.expect(lambda m: "ready" in m)
        b.p.stdin.close()
        self.assertEqual(b.p.wait(5), 0)
        b.p.stdout.close()


class Packaging(unittest.TestCase):
    def test_unit_and_activation(self):
        unit = (ROOT / "distro/systemd/user/citronos-settingsd.service").read_text()
        for line in ("Type=dbus", "BusName=org.citronos.Settings1", "ExecStart=/usr/bin/env gg-settingsd",
                     "PartOf=citronos-session.target", "Restart=on-failure"):
            self.assertIn(line, unit)
        activation = (ROOT / "distro/dbus/org.citronos.Settings1.service").read_text()
        self.assertIn("Name=org.citronos.Settings1", activation)
        self.assertIn("SystemdService=citronos-settingsd.service", activation)
        install = (ROOT / "scripts/install.sh").read_text()
        self.assertIn("services/settingsd/settingsd.py", install)
        self.assertIn("dbus-1/services/org.citronos.Settings1.service", install)
        self.assertIn('"$BIN/gg-settingsd"', install)
        build = (ROOT / "distro/archiso/build.sh").read_text()
        self.assertIn('["/usr/local/bin/gg-settingsd"]="0:0:755"', build)
        self.assertIn('["/usr/lib/golden-gate/settingsd.py"]="0:0:755"', build)

    def test_changes(self):
        sys.path.insert(0, str(SERVICE.parent))
        try:
            import settingsd
        except ImportError:
            self.skipTest("needs dbus-next")
        old = {"dock": {"size": 54, "pinned": ["a"]}, "glass": "clear", "reduceMotion": False}
        new = {"dock": {"size": 60, "pinned": ["a"]}, "glass": "clear", "reduceMotion": 0, "menuBar": {"seconds": True}}
        self.assertEqual(list(settingsd.changes(old, new)),
                         [("dock.size", 60), ("menuBar.seconds", True), ("reduceMotion", 0)])
        self.assertEqual(list(settingsd.changes(new, {})), [("dock.pinned", None), ("dock.size", None), ("glass", None),
                                                           ("menuBar.seconds", None), ("reduceMotion", None)])
        self.assertEqual(list(settingsd.changes({"widgets": [1]}, {"widgets": {"a": 1}})), [("widgets", {"a": 1})],
                         "a list that became an object is sent whole")


if __name__ == "__main__":
    unittest.main()
