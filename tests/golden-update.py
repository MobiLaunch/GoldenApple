#!/usr/bin/env python3
"""Software Update installs Golden Gate from GitHub.

A stand-in GitHub API serves this checkout as the newest commit of a private
repository; the update is installed into a staging root with the real
scripts/install.sh. Checks that a token is needed and used, that the notes
come from the compare API, that the runtime and version record are replaced,
and that an account's shell is refreshed while a file its user edited is
kept (with the new one beside it)."""
from __future__ import annotations

import http.server
import io
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOKEN = "github_pat_" + "T" * 30
BLIND = "github_pat_" + "B" * 30        # a valid token that can't see the repository
SHA = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip() or "f" * 40
OLD = "0" * 40
BRANCH = "claude/linux-macos-golden-gate-ui-pckc7s"


def snapshot() -> bytes:
    """This checkout as GitHub's tarball of a commit (one top folder)."""
    buf = io.BytesIO()
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True).stdout.split(b"\0")
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for f in files:
            if f:
                rel = f.decode()
                p = ROOT / rel
                if p.exists() or p.is_symlink():
                    tar.add(p, arcname=f"MobiLaunch-GoldenApple-{SHA[:7]}/{rel}", recursive=False)
    return buf.getvalue()


ARCHIVE = snapshot()


class FakeGitHub(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization")
        if auth and auth not in (f"Bearer {TOKEN}", f"Bearer {BLIND}"):
            return self.reply(401, {"message": "Bad credentials"})
        if auth != f"Bearer {TOKEN}":
            return self.reply(404, {"message": "Not Found"})
        base = "/repos/MobiLaunch/GoldenApple"
        if self.path == base:
            return self.reply(200, {"full_name": "MobiLaunch/GoldenApple", "private": True})
        if self.path == f"{base}/commits/{BRANCH}":
            return self.reply(200, {"sha": SHA, "commit": {"message": "Newest work\n\ndetails",
                                                         "committer": {"date": "2026-10-04T10:00:00Z"}}})
        if self.path == f"{base}/compare/{OLD}...{SHA}":
            return self.reply(200, {"ahead_by": 2, "commits": [
                {"commit": {"message": "First change"}}, {"commit": {"message": "Second change\n\nmore"}}]})
        if self.path == f"{base}/tarball/{SHA}":
            self.send_response(200)
            self.send_header("Content-Type", "application/x-gzip")
            self.send_header("Content-Length", str(len(ARCHIVE)))
            self.end_headers()
            self.wfile.write(ARCHIVE)
            return
        self.reply(404, {"message": "Not Found"})

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


SERVER = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeGitHub)
threading.Thread(target=SERVER.serve_forever, daemon=True).start()

STAGE = Path(tempfile.mkdtemp(prefix="gg-update-root-"))
os.environ["GG_UPDATE_API"] = f"http://127.0.0.1:{SERVER.server_port}"
os.environ["GG_UPDATE_ROOT"] = str(STAGE)
sys.path.insert(0, str(ROOT / "apps/settings"))
import golden_update  # noqa: E402

# An account to update: the first real user on this machine, or skip that part.
USER = next((u for u in pwd.getpwall() if 1000 <= u.pw_uid < 60000 and not u.pw_shell.endswith(("nologin", "false"))), None)


class GoldenUpdate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The system as installed from an older ISO.
        (STAGE / "usr/share/golden-gate").mkdir(parents=True)
        (STAGE / "usr/share/golden-gate/version.json").write_text(json.dumps(
            {"repo": "MobiLaunch/GoldenApple", "branch": BRANCH, "commit": OLD}))
        skel = STAGE / "etc/skel/.config"
        for rel, text in (("hypr/hyprland.conf", "old hyprland\n"), ("gtk-4.0/gtk.css", "old gtk\n")):
            (skel / rel).parent.mkdir(parents=True, exist_ok=True)
            (skel / rel).write_text(text)
        if USER:
            conf = STAGE / USER.pw_dir.lstrip("/") / ".config"
            (conf / "quickshell/golden-gate").mkdir(parents=True)
            (conf / "quickshell/golden-gate/old.qml").write_text("old shell")
            (conf / "hypr").mkdir(parents=True)
            (conf / "hypr/hyprland.conf").write_text("old hyprland\n# my own binds\n")   # edited
            (conf / "gtk-4.0").mkdir(parents=True)
            (conf / "gtk-4.0/gtk.css").write_text("old gtk\n")                            # untouched

    def test_1_private_repository_needs_a_token(self):
        status = golden_update.check()
        self.assertFalse(status["available"])
        self.assertTrue(status["needsToken"])

    def test_1b_says_why_a_token_fails(self):
        golden_update.set_source("MobiLaunch/GoldenApple", BRANCH, "github_pat_" + "X" * 30)
        status = golden_update.check()
        self.assertTrue(status["needsToken"])
        self.assertIn("didn't accept the access token", status["error"])
        golden_update.set_source("MobiLaunch/GoldenApple", BRANCH, BLIND)
        status = golden_update.check()
        self.assertTrue(status["needsToken"])
        self.assertIn("can't see MobiLaunch/GoldenApple", status["error"])
        self.assertIn("Only select repositories", status["error"])
        # Pasted with a line break, quotes and a Bearer prefix: still the token.
        golden_update.set_source("MobiLaunch/GoldenApple", "no-such-branch", f' "Bearer {TOKEN[:20]}\n{TOKEN[20:]}" ')
        self.assertEqual(golden_update.source()["token"], TOKEN)
        status = golden_update.check()
        self.assertFalse(status["needsToken"])
        self.assertIn("no branch named", status["error"])
        with self.assertRaises(ValueError):
            golden_update.set_source("MobiLaunch/GoldenApple", BRANCH, "my password")

    @unittest.skipUnless(os.geteuid() == 0, "saving the update source needs root")
    def test_1c_save_asks_github_first(self):
        def save(token):
            proc = subprocess.run([sys.executable, str(ROOT / "apps/settings/update-helper.py"), "set-source"],
                                  input=json.dumps({"repo": "MobiLaunch/GoldenApple", "branch": BRANCH, "token": token}) + "\n",
                                  capture_output=True, text=True, env=os.environ, timeout=60)
            return proc.returncode, [json.loads(l) for l in proc.stdout.splitlines() if l.startswith("{")]
        code, events = save("github_pat_" + "X" * 30)
        self.assertNotEqual(code, 0)
        self.assertIn("didn't accept the access token", events[-1]["message"])
        code, events = save(BLIND)
        self.assertNotEqual(code, 0)
        self.assertIn("can't see", events[-1]["message"])
        self.assertNotEqual(golden_update.source()["token"], BLIND)       # refused tokens aren't kept
        code, events = save(TOKEN)
        self.assertEqual(code, 0, events)
        self.assertEqual(events[-1], {"event": "done", "message": "Saved."})
        self.assertEqual(golden_update.source()["token"], TOKEN)

    def test_2_check_with_token(self):
        golden_update.set_source("MobiLaunch/GoldenApple", BRANCH, TOKEN)
        status = golden_update.check()
        self.assertTrue(status["available"], status)
        self.assertEqual(status["latest"], SHA)
        self.assertEqual(status["notes"], ["Second change", "First change"])
        self.assertEqual(status["ahead"], 2)
        with self.assertRaises(ValueError):
            golden_update.set_source("not a repo", BRANCH, None)
        with self.assertRaises(ValueError):
            golden_update.set_source("a/b", "../etc", None)

    def test_3_install(self):
        events = []
        ok = golden_update.apply(lambda event, **kw: events.append((event, kw)))
        self.assertTrue(ok, events)
        self.assertFalse([e for e in events if e[0] == "error"], events)
        version = json.loads((STAGE / "usr/share/golden-gate/version.json").read_text())
        self.assertEqual(version["commit"], SHA)
        self.assertEqual(version["branch"], BRANCH)
        self.assertTrue((STAGE / "usr/share/golden-gate/apps/settings/golden_update.py").exists())
        self.assertTrue((STAGE / "usr/share/polkit-1/actions/org.goldengate.update.policy").exists())
        self.assertFalse((STAGE / "etc/sudoers.d/10-golden-live").exists())
        self.assertFalse(golden_update.check()["available"])
        if USER:
            conf = STAGE / USER.pw_dir.lstrip("/") / ".config"
            self.assertTrue((conf / "quickshell/golden-gate/shell.qml").exists())
            self.assertFalse((conf / "quickshell/golden-gate/old.qml").exists())
            self.assertEqual((conf / "gtk-4.0/gtk.css").read_text(),
                             (STAGE / "etc/skel/.config/gtk-4.0/gtk.css").read_text())
            self.assertIn("my own binds", (conf / "hypr/hyprland.conf").read_text())
            self.assertTrue((conf / "hypr/hyprland.conf.golden-gate-new").exists())
            self.assertTrue(any("Kept your edited" in kw.get("message", "") for e, kw in events if e == "notice"))


class FromUsb(unittest.TestCase):
    """The command line, as from the live ISO: an update bundle installed onto
    a Golden Gate system mounted somewhere else, whose accounts are its own."""
    def test_bundle_onto_a_mounted_system(self):
        work = Path(tempfile.mkdtemp(prefix="gg-usb-"))
        try:
            bundle = work / "golden-gate-update.tar.gz"
            subprocess.run(["bash", str(ROOT / "scripts/make-update-bundle.sh"), str(bundle)],
                           check=True, capture_output=True)
            target = work / "disk"
            (target / "usr/share/golden-gate").mkdir(parents=True)
            (target / "etc").mkdir()
            (target / "etc/passwd").write_text("root:x:0:0::/root:/bin/bash\n"
                                               "jordan:x:1000:1000::/home/jordan:/bin/bash\n")
            shell = target / "home/jordan/.config/quickshell/golden-gate"
            shell.mkdir(parents=True)
            (shell / "old.qml").write_text("old")
            env = {k: v for k, v in os.environ.items() if not k.startswith("GG_UPDATE")}
            proc = subprocess.run([sys.executable, str(ROOT / "apps/settings/golden_update.py"), "install-local",
                                   "--from", str(bundle), "--root", str(target)],
                                  capture_output=True, text=True, env=env, timeout=900)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            version = json.loads((target / "usr/share/golden-gate/version.json").read_text())
            self.assertEqual(version["commit"], SHA)
            self.assertTrue((shell / "shell.qml").exists())
            self.assertFalse((shell / "old.qml").exists())
            if os.geteuid() == 0:
                self.assertEqual((shell / "shell.qml").stat().st_uid, 1000)
            self.assertFalse((target / "etc/systemd/system/gg-live-home.service").exists())
        finally:
            subprocess.run(["rm", "-rf", str(work)])


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        subprocess.run(["rm", "-rf", str(STAGE)])
