#!/usr/bin/env python3
"""Offline Messages media / video integration and safe delivery regression tests."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "apps/messages/media.py"
CALLS = ROOT / "apps/messages/call-links.py"


def run_py(source, *args, env=None, stdin=None):
    p = subprocess.run([sys.executable, str(source), *map(str, args)],
                       input=stdin, capture_output=True, text=True,
                       timeout=12, env=env)
    try:
        data = json.loads(p.stdout)
    except Exception:
        raise AssertionError((p.returncode, p.stdout, p.stderr))
    return p.returncode, data


class FakeBlueBubbles(http.server.BaseHTTPRequestHandler):
    requests = []
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        self.requests.append((self.path, body, self.headers.get("Content-Type")))
        response = b'{"status":200,"message":"accepted"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)
    def log_message(self, *args):
        pass


class MediaContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.config = self.dir / "private.json"
        self.env = {**os.environ, "GG_MESSAGES_MEDIA_CONFIG": str(self.config)}
        self.image = self.dir / "Holiday Photo.png"
        self.image.write_bytes(b"\x89PNG\r\n" + b"image-data" * 10)

    def test_unconfigured_media_is_not_falsely_enabled(self):
        ret, state = run_py(MEDIA, "status", env=self.env)
        self.assertEqual(ret, 0)
        self.assertFalse(state["ready"])
        ret, response = run_py(MEDIA, "send", self.image, "+15551231234", env=self.env)
        self.assertNotEqual(ret, 0)
        self.assertFalse(response["ok"])

    def test_file_validation(self):
        ret, data = run_py(MEDIA, "inspect", self.image, env=self.env)
        self.assertEqual(ret, 0)
        self.assertEqual(data["type"], "image")
        self.assertEqual(data["mime"], "image/png")
        for path in ("unsafe.exe", "invalid.txt"):
            file = self.dir / path
            file.write_text("not-media")
            ret, data = run_py(MEDIA, "inspect", file, env=self.env)
            self.assertNotEqual(ret, 0)
        link = self.dir / "trick.png"
        link.symlink_to(self.image)
        ret, data = run_py(MEDIA, "inspect", link, env=self.env)
        self.assertNotEqual(ret, 0)
        large = self.dir / "too-large.mov"
        with large.open("wb") as f:
            f.truncate(101 * 1024 * 1024)
        ret, data = run_py(MEDIA, "inspect", large, env=self.env)
        self.assertNotEqual(ret, 0)

    def test_private_configuration_and_no_plain_http_to_remote_host(self):
        ret, r = run_py(MEDIA, "configure", env=self.env, stdin=json.dumps({
            "url": "http://evil.example", "password": "topsecret"
        }))
        self.assertNotEqual(ret, 0)
        self.assertFalse(self.config.exists())
        ret, r = run_py(MEDIA, "configure", env=self.env, stdin=json.dumps({
            "url": "https://example.test", "password": "topsecret"
        }))
        self.assertEqual(ret, 0)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        self.assertNotIn("topsecret", str(r))
        ret, state = run_py(MEDIA, "status", env=self.env)
        self.assertTrue(state["ready"])
        self.config.chmod(0o644)
        ret, state = run_py(MEDIA, "status", env=self.env)
        self.assertNotEqual(ret, 0)
        self.assertIn("chmod", state["error"])

    def test_real_multipart_request_submission_through_fake_server(self):
        FakeBlueBubbles.requests = []
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeBlueBubbles)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        config = {
            "url": f"http://127.0.0.1:{server.server_port}",
            "password": "secret", "provider": "bluebubbles"
        }
        r, result = run_py(MEDIA, "configure", env=self.env, stdin=json.dumps(config))
        self.assertEqual(r, 0, result)
        code, result = run_py(MEDIA, "send", self.image, "+15551231234", "A vacation picture", env=self.env)
        self.assertEqual(code, 0, result)
        self.assertEqual(result["result"], "submitted")
        self.assertEqual(result["provider"], "bluebubbles")
        self.assertEqual(len(FakeBlueBubbles.requests), 1)
        uri, raw, typ = FakeBlueBubbles.requests[0]
        self.assertIn("/api/v1/message/attachment?password=secret", uri)
        self.assertIn(b"\r\n\r\n+15551231234\r\n", raw)
        self.assertIn(b"\r\n\r\nA vacation picture\r\n", raw)
        self.assertIn(self.image.read_bytes(), raw)
        self.assertIn("multipart/form-data", typ)
        code, result = run_py(MEDIA, "send", self.image, "another@domain.example\r\nInjected", env=self.env)
        self.assertNotEqual(code, 0)
        self.assertEqual(len(FakeBlueBubbles.requests), 1)

    def test_webrtc_room_is_random_and_facetime_links_are_validated(self):
        a, one = run_py(CALLS, "create", env=self.env)
        b, two = run_py(CALLS, "create", env=self.env)
        self.assertEqual(a, 0)
        self.assertEqual(b, 0)
        self.assertNotEqual(one["url"], two["url"])
        self.assertTrue(one["url"].startswith("https://meet.jit.si/GoldenGate-"))
        ok, joined = run_py(CALLS, "join", "https://facetime.apple.com/join/#test", env=self.env)
        self.assertEqual(ok, 0, joined)
        self.assertEqual(joined["type"], "facetime")
        for link in ("http://facetime.apple.com/join/abc", "https://facetime.apple.com.evil.org/join/abc",
                     "https://evil.com/join", "https://facetime.apple.com/"):
            rc, result = run_py(CALLS, "join", link, env=self.env)
            self.assertNotEqual(rc, 0, link)

    def test_messages_ui_keeps_transport_capabilities_explicit(self):
        qml = (ROOT / "apps/messages.qml").read_text()
        self.assertIn("ContactCard {", qml)
        self.assertIn("Add Photos or Videos", qml)
        self.assertIn("gg-web", qml)
        self.assertIn("iMessage Media Relay", qml)
        self.assertIn("mediaReady", qml)
        # The composer dispatches via app.send(), which delegates media sends
        # to sendMedia() only when an attachment has been validated.
        self.assertIn("function sendMedia()", qml)
        self.assertIn("if (mediaPath) { sendMedia(); return }", qml)
        self.assertIn("faceTimeInput", qml)
        self.assertIn('server(record)', (ROOT / "apps/messages/media.py").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
