#!/usr/bin/env python3
"""AirDrop: two services on this machine find each other and share files
over the LocalSend protocol, through the same control socket the app uses."""
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
    def __init__(self, root: Path, name: str, port: int, peers: str, http=False):
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
        if http:
            env["GG_AIRDROP_HTTP"] = "1"
        (self.root / "config").mkdir()
        (self.root / "config/golden-gate").mkdir()
        (self.root / "config/golden-gate/airdrop.json").write_text(json.dumps({"alias": name}))
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
        self.a = Device(root, "Alpha", pa, f"127.0.0.1:{pb}")
        self.b = Device(root, "Bravo", pb, f"127.0.0.1:{pa}", http=self.id().endswith("http"))
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

    def test_plain_http_device(self):
        done = self.share(True)
        self.assertEqual(done["state"], "sent", done)

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
