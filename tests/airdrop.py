#!/usr/bin/env python3
"""AirDrop: two services on this machine find each other and share files
over the LocalSend protocol, through the same control socket the app uses.

Receiving is off until it's turned on, and while it's off nothing listens
on the network; "Everyone for 10 Minutes" turns itself off; plain HTTP is
never used, in either direction (CS2-017)."""
from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "apps/airdrop/airdropd.py"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class Device:
    def __init__(self, root: Path, name: str, port: int, peers: str, settings=None, env_extra=None):
        self.root = root / name
        self.downloads = self.root / "Downloads"
        self.downloads.mkdir(parents=True)
        self.sock_path = self.root / "control.sock"
        env = os.environ.copy()
        env.update({
            "HOME": str(self.root), "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"), "XDG_RUNTIME_DIR": str(self.root),
            "GG_AIRDROP_PORT": str(port), "GG_AIRDROP_SOCKET": str(self.sock_path),
            "GG_AIRDROP_DOWNLOADS": str(self.downloads), "GG_AIRDROP_PEERS": peers,
            "PATH": "/usr/bin:/bin",          # no notify-send: requests wait for the socket
        })
        env.update(env_extra or {})
        self.port = port
        self.settings = self.root / "config/golden-gate/airdrop.json"
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({"alias": name, **(settings or {})}))
        self.proc = subprocess.Popen([sys.executable, str(SERVICE), "serve"], env=env,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for _ in range(100):
            if self.sock_path.exists():
                break
            time.sleep(0.1)
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(str(self.sock_path))
        self.sock.settimeout(0.2)
        self.buf = b""
        self.send({"cmd": "hello"})

    def send(self, msg):
        self.sock.sendall((json.dumps(msg) + "\n").encode())

    def events(self, until, timeout=20):
        """Read events until `until(event)` is true; return that event."""
        end = time.time() + timeout
        while time.time() < end:
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                ev = json.loads(line)
                if until(ev):
                    return ev
            try:
                data = self.sock.recv(65536)
                if not data:
                    break
                self.buf += data
            except socket.timeout:
                pass
        raise AssertionError("timed out waiting for an event")

    def close(self):
        self.sock.close()
        self.proc.terminate()
        self.proc.stdout.close()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


class AirDropTransfer(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        pa, pb = free_port(), free_port()
        # Alpha has never turned receiving on: it can still find and send.
        self.a = Device(root, "Alpha", pa, f"127.0.0.1:{pb}")
        self.b = Device(root, "Bravo", pb, f"127.0.0.1:{pa}", settings={"discoverable": "everyone"})
        self.a.events(lambda e: e.get("event") == "state")
        self.b.events(lambda e: e.get("event") == "state")
        self.a.send({"cmd": "scan"})
        ev = self.a.events(lambda e: e.get("event") == "peers" and any(p["alias"] == "Bravo" for p in e["peers"]))
        self.bravo = next(p for p in ev["peers"] if p["alias"] == "Bravo")["fingerprint"]
        self.payload = root / "Holiday photo.jpg"
        self.payload.write_bytes(os.urandom(3 * 1024 * 1024 + 17))

    def tearDown(self):
        self.a.close()
        self.b.close()
        self.tmp.cleanup()

    def share(self, accept: bool):
        self.a.send({"cmd": "send", "to": self.bravo, "paths": [str(self.payload)]})
        req = self.b.events(lambda e: e.get("event") == "request")
        self.assertEqual(req["from"], "Alpha")
        self.assertEqual(req["files"], ["Holiday photo.jpg"])
        self.b.send({"cmd": "answer", "id": req["id"], "accept": accept})
        return self.a.events(lambda e: e.get("event") == "transfer" and e["state"] in ("sent", "declined", "failed"))

    def test_accepted_file_arrives_in_downloads(self):
        done = self.share(True)
        self.assertEqual(done["state"], "sent", done)
        got = self.b.events(lambda e: e.get("event") == "received")
        self.assertEqual(len(got["paths"]), 1)
        self.assertEqual(Path(got["paths"][0]).read_bytes(), self.payload.read_bytes())
        self.assertEqual(Path(got["paths"][0]).parent, self.b.downloads)

    def test_declined_request_sends_nothing(self):
        done = self.share(False)
        self.assertEqual(done["state"], "declined", done)
        self.assertEqual(list(self.b.downloads.iterdir()), [])

    def test_a_sender_with_receiving_off_listens_for_nothing(self):
        done = self.share(True)
        self.assertEqual(done["state"], "sent", done)
        self.assertFalse(listening(self.a.port))

    def test_folder_keeps_its_structure(self):
        folder = self.payload.parent / "Trip"
        (folder / "day 1").mkdir(parents=True)
        (folder / "day 1" / "a.txt").write_text("one")
        (folder / "b.txt").write_text("two")
        self.a.send({"cmd": "send", "to": self.bravo, "paths": [str(folder)]})
        req = self.b.events(lambda e: e.get("event") == "request")
        self.assertEqual(req["count"], 2)
        self.b.send({"cmd": "answer", "id": req["id"], "accept": True})
        self.b.events(lambda e: e.get("event") == "received")
        self.assertEqual((self.b.downloads / "Trip" / "day 1" / "a.txt").read_text(), "one")
        self.assertEqual((self.b.downloads / "Trip" / "b.txt").read_text(), "two")


def listening(port):
    """Whether anything takes connections on the TCP port, or holds the UDP one."""
    try:
        socket.create_connection(("127.0.0.1", port), timeout=1).close()
        return True
    except OSError:
        pass
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        u.bind(("", port))
        return False
    except OSError:
        return True
    finally:
        u.close()


class Receiving(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.devices = []

    def tearDown(self):
        for d in self.devices:
            d.close()
        self.tmp.cleanup()

    def device(self, **kw):
        d = Device(self.root, f"D{len(self.devices)}", free_port(), "", **kw)
        self.devices.append(d)
        return d

    def test_off_by_default_and_nothing_listens(self):
        d = self.device()
        state = d.events(lambda e: e.get("event") == "state")
        self.assertEqual(state["discoverable"], "off")
        self.assertFalse(state["receiving"])
        self.assertFalse(listening(d.port), "no HTTPS and no discovery port while receiving is off")

    def test_everyone_for_ten_minutes_turns_itself_off(self):
        d = self.device(env_extra={"GG_AIRDROP_EVERYONE_SECONDS": "3"})
        d.events(lambda e: e.get("event") == "state")
        before = time.time()
        d.send({"cmd": "set", "discoverable": "everyone-10min"})
        on = d.events(lambda e: e.get("event") == "state" and e["receiving"])
        self.assertEqual(on["discoverable"], "everyone")
        self.assertAlmostEqual(on["until"], before + 3, delta=2)
        self.assertTrue(listening(d.port))
        off = d.events(lambda e: e.get("event") == "state" and not e["receiving"], timeout=15)
        self.assertEqual(off["discoverable"], "off")
        self.assertIsNone(off["until"])
        self.assertFalse(listening(d.port))
        self.assertEqual(json.loads(d.settings.read_text())["discoverable"], "off")

    def test_everyone_stays_on_and_off_stops_listening(self):
        d = self.device()
        d.events(lambda e: e.get("event") == "state")
        d.send({"cmd": "set", "discoverable": "everyone"})
        on = d.events(lambda e: e.get("event") == "state" and e["receiving"])
        self.assertIsNone(on["until"])
        self.assertTrue(listening(d.port))
        d.send({"cmd": "set", "discoverable": "off"})
        d.events(lambda e: e.get("event") == "state" and not e["receiving"])
        self.assertFalse(listening(d.port))

    def test_plain_http_is_never_used(self):
        # A device that offers only plain HTTP: the sweep speaks TLS to it,
        # never an HTTP request in the clear, and it isn't listed.
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(8)
        server.settimeout(0.2)
        heard = []

        def accept():
            while not stop:
                try:
                    c, _ = server.accept()
                except OSError:
                    continue
                c.settimeout(2)
                try:
                    heard.append(c.recv(16))
                except OSError:
                    pass
                c.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}')
                c.close()
        import threading
        stop = False
        t = threading.Thread(target=accept, daemon=True)
        t.start()
        d = Device(self.root, "Sweep", free_port(), f"127.0.0.1:{server.getsockname()[1]}")
        self.devices.append(d)
        try:
            d.events(lambda e: e.get("event") == "state")
            d.send({"cmd": "scan"})
            peers = d.events(lambda e: e.get("event") == "peers")
            self.assertEqual(peers["peers"], [])
            self.assertTrue(heard, "the sweep reached the device")
            for first in heard:
                self.assertEqual(first[:1], b"\x16", f"a TLS handshake, not {first!r}")
        finally:
            stop = True
            t.join(2)
            server.close()


class Clock(unittest.TestCase):
    def test_ten_minutes_by_the_clock(self):
        sys.path.insert(0, str(SERVICE.parent))
        import airdropd
        with tempfile.TemporaryDirectory() as t:
            old = {k: os.environ.get(k) for k in ("XDG_CONFIG_HOME", "XDG_DATA_HOME")}
            os.environ.update(XDG_CONFIG_HOME=t, XDG_DATA_HOME=t)
            try:
                a = airdropd.AirDrop()
            finally:
                for k, v in old.items():
                    os.environ.pop(k) if v is None else os.environ.__setitem__(k, v)
            self.assertEqual(a.discoverable, "off", "a fresh settings file is off")
            a.now = lambda: 1000.0
            a.choose("everyone-10min")
            self.assertEqual(a.until, 1000.0 + airdropd.EVERYONE_FOR)
            a.now = lambda: 1000.0 + airdropd.EVERYONE_FOR - 1
            self.assertEqual(a.discoverable, "everyone")
            a.now = lambda: 1000.0 + airdropd.EVERYONE_FOR
            self.assertEqual(a.discoverable, "off")
            self.assertIsNone(a.until)
            a.choose("everyone")
            self.assertEqual(a.discoverable, "everyone")
            self.assertIsNone(a.until)


class FileNames(unittest.TestCase):
    def test_names_cannot_leave_downloads(self):
        sys.path.insert(0, str(SERVICE.parent))
        import airdropd
        self.assertIsNone(airdropd.safe_relative("../../.bashrc"))
        self.assertIsNone(airdropd.safe_relative(""))
        self.assertEqual(str(airdropd.safe_relative("/etc/passwd")), "etc/passwd")
        self.assertEqual(str(airdropd.safe_relative("Trip\\day 1/a.txt")), "Trip/day 1/a.txt")


class OneDaemon(unittest.TestCase):
    def test_second_daemon_steps_aside(self):
        # One already answers on the control socket: a second one (the window
        # starts one if it can't connect) mustn't take the socket and port.
        with tempfile.TemporaryDirectory() as t:
            sock = Path(t) / "ctl.sock"
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.bind(str(sock))
            listener.listen(1)
            try:
                p = subprocess.run([sys.executable, str(SERVICE), "serve"], capture_output=True, text=True, timeout=20,
                                   env=dict(os.environ, GG_AIRDROP_SOCKET=str(sock), HOME=t, XDG_CONFIG_HOME=t, XDG_RUNTIME_DIR=t))
            finally:
                listener.close()
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("already running", p.stdout)
            self.assertTrue(sock.exists(), "the running daemon keeps its socket")


if __name__ == "__main__":
    unittest.main(verbosity=2)
