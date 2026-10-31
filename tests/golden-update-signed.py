#!/usr/bin/env python3
"""Software Update installs only genuine, newer CitronOS releases (CS2-003).

A stand-in GitHub serves releases built and signed with the real
scripts/make-release.sh and a key made for this test. The system trusts only
that key. Checked:
  - the stable channel takes the newest release, beta also pre-releases;
  - a signed release installs, with its version recorded;
  - a changed file, a release with no signature, a release signed by another
    key and an older version are all refused, and nothing is installed;
  - an update.json from before channels counts as stable;
  - the token isn't sent on when GitHub redirects a download elsewhere;
  - install-local wants a signed bundle unless told --unsigned.
"""
from __future__ import annotations

import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORK = Path(tempfile.mkdtemp(prefix="gg-signed-"))
STAGE = WORK / "root"
KEYS = WORK / "keys"
REPO = "MobiLaunch/GoldenApple"


def keypair(name: str) -> Path:
    key = WORK / f"{name}.key"
    subprocess.run(["openssl", "genpkey", "-algorithm", "ed25519", "-out", str(key)], check=True, capture_output=True)
    return key


def release(version: str, key: Path, channel: str = "stable", trusted: Path = KEYS) -> Path:
    out = WORK / ("rel-" + version + "-" + key.stem)
    subprocess.run(["bash", str(ROOT / "scripts/make-release.sh"), version, str(key), str(out), channel],
                   check=True, capture_output=True, env={**os.environ, "GG_RELEASE_KEYS": str(trusted)})
    return out


TRUSTED, OTHER = keypair("trusted"), keypair("other")
KEYS.mkdir()
subprocess.run(["openssl", "pkey", "-in", str(TRUSTED), "-pubout", "-out", str(KEYS / "citronos-test.pem")], check=True)
OTHER_KEYS = WORK / "other-keys"
OTHER_KEYS.mkdir()
subprocess.run(["openssl", "pkey", "-in", str(OTHER), "-pubout", "-out", str(OTHER_KEYS / "other.pem")], check=True)

# The releases GitHub has, newest first, as GitHub lists them. Release.qml
# says 4.0, so these are 4.0.x (and a 4.0.9 beta).
GOOD = release("4.0.2", TRUSTED)
BETA = release("4.0.9-beta.1", TRUSTED, "beta")
TAMPERED = release("4.0.3", TRUSTED)
UNSIGNED = release("4.0.4", TRUSTED)
FOREIGN = release("4.0.5", OTHER, trusted=OTHER_KEYS)
with open(TAMPERED / "citronos-4.0.3.tar.gz", "ab") as f:
    f.write(b"\0" * 512)                                           # changed after signing
(UNSIGNED / "citronos-4.0.4.manifest.json.sig").unlink()

RELEASES = {"v4.0.9-beta.1": (BETA, True), "v4.0.5": (FOREIGN, False), "v4.0.4": (UNSIGNED, False),
            "v4.0.3": (TAMPERED, False), "v4.0.2": (GOOD, False)}
SHOWN = ["v4.0.9-beta.1", "v4.0.2"]          # which ones the API lists; tests change it
ASSETS: dict[int, Path] = {}
SEEN_AUTH: list[str | None] = []          # at the storage host
GITHUB_AUTH: list[str | None] = []        # at GitHub, for the same downloads


def listing(tag: str) -> dict:
    folder, pre = RELEASES[tag]
    assets = []
    for f in sorted(folder.iterdir()):
        aid = len(ASSETS) + 1
        ASSETS[aid] = f
        assets.append({"id": aid, "name": f.name, "url": f"{API}/repos/{REPO}/releases/assets/{aid}"})
    return {"tag_name": tag, "name": "CitronOS " + tag[1:], "prerelease": pre, "draft": False,
            "published_at": "2026-10-24T10:00:00Z", "body": "## What's Changed\n- Signed updates\n- Wi-Fi fix\n",
            "assets": assets}


class Storage(http.server.BaseHTTPRequestHandler):
    """Where GitHub really keeps release files: another host."""
    def do_GET(self):
        SEEN_AUTH.append(self.headers.get("Authorization"))
        data = ASSETS[int(self.path.strip("/"))].read_bytes()
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


class FakeGitHub(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        base = f"/repos/{REPO}"
        if self.path.startswith(f"{base}/releases?"):
            return self.reply(200, [listing(t) for t in SHOWN])
        if self.path.startswith(f"{base}/releases/tags/"):
            tag = self.path.rsplit("/", 1)[-1]
            return self.reply(200, listing(tag)) if tag in RELEASES else self.reply(404, {"message": "Not Found"})
        if self.path.startswith(f"{base}/releases/assets/"):
            GITHUB_AUTH.append(self.headers.get("Authorization"))
            self.send_response(302)
            self.send_header("Location", f"http://localhost:{STORAGE.server_port}/{self.path.rsplit('/', 1)[-1]}")
            self.end_headers()
            return
        if self.path == base:
            return self.reply(200, {"full_name": REPO})
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
STORAGE = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Storage)
for s in (SERVER, STORAGE):
    threading.Thread(target=s.serve_forever, daemon=True).start()
API = f"http://127.0.0.1:{SERVER.server_port}"
os.environ.update(GG_UPDATE_API=API, GG_UPDATE_ROOT=str(STAGE), GG_RELEASE_KEYS=str(KEYS))
sys.path.insert(0, str(ROOT / "apps/settings"))
import golden_update  # noqa: E402

TOKEN = "github_pat_" + "T" * 30


def installed_version() -> dict:
    return json.loads((STAGE / "usr/share/golden-gate/version.json").read_text())


class SignedReleases(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (STAGE / "usr/share/golden-gate").mkdir(parents=True)
        (STAGE / "usr/share/golden-gate/version.json").write_text(json.dumps(
            {"repo": REPO, "channel": "stable", "version": "4.0.1", "commit": "0" * 40}))
        (STAGE / "etc/golden-gate").mkdir(parents=True)
        # From before channels: a branch, no channel. It must mean stable.
        (STAGE / "etc/golden-gate/update.json").write_text(json.dumps({"repo": REPO, "branch": "attacker-branch"}))
        (STAGE / "etc/golden-gate/update-token").write_text(TOKEN + "\n")

    def setUp(self):
        SHOWN[:] = ["v4.0.9-beta.1", "v4.0.2"]

    def apply(self) -> tuple[str, list]:
        events: list = []
        outcome = golden_update.apply(lambda e, **kw: events.append((e, kw)))
        return outcome, events

    def test_1_old_settings_mean_stable(self):
        self.assertEqual(golden_update.source()["channel"], "stable")

    def test_2_channels_pick_their_release(self):
        status = golden_update.check()
        self.assertTrue(status["available"], status)
        self.assertEqual(status["latest"], "v4.0.2", "stable skips the pre-release")
        self.assertTrue(status["signed"])
        self.assertEqual(status["notes"], ["Signed updates", "Wi-Fi fix"])
        golden_update.set_source(REPO, "main", None, "beta")
        try:
            self.assertEqual(golden_update.check()["latest"], "v4.0.9-beta.1")
        finally:
            golden_update.set_source(REPO, "main", None, "stable")

    def refused(self, tag: str, why: str):
        SHOWN[:] = [tag]
        before = installed_version()
        outcome, events = self.apply()
        self.assertEqual(outcome, "failed", events)
        errors = [kw["message"] for e, kw in events if e == "error"]
        self.assertTrue(errors and why in errors[-1], errors)
        self.assertEqual(installed_version(), before, "nothing was installed")

    def test_3_a_changed_file_is_refused(self):
        self.refused("v4.0.3", "isn't the one CitronOS signed")

    def test_3b_an_unsigned_release_is_refused(self):
        self.refused("v4.0.4", "isn't a signed CitronOS release")

    def test_3c_another_key_is_refused(self):
        self.refused("v4.0.5", "isn't signed by CitronOS")

    def test_3d_no_trusted_key_no_update(self):
        empty = WORK / "no-keys"
        empty.mkdir(exist_ok=True)
        old, golden_update.RELEASE_KEYS = golden_update.RELEASE_KEYS, empty
        try:
            self.refused("v4.0.2", "has no release key")
        finally:
            golden_update.RELEASE_KEYS = old

    def test_4_an_older_release_is_refused(self):
        folder = GOOD
        manifest = (folder / "citronos-4.0.2.manifest.json").read_bytes()
        sig = (folder / "citronos-4.0.2.manifest.json.sig").read_bytes()
        bundle = folder / "citronos-4.0.2.tar.gz"
        info = golden_update.check_bundle(bundle, manifest, sig, "4.0.1", "v4.0.2")
        self.assertEqual(info["version"], "4.0.2")
        for newer in ("4.0.2", "4.0.10", "4.1"):
            with self.assertRaises(golden_update.UpdateRefused):
                golden_update.check_bundle(bundle, manifest, sig, newer, "v4.0.2")
        with self.assertRaises(golden_update.UpdateRefused):
            golden_update.check_bundle(bundle, manifest, sig, "4.0.1", "v4.0.7")   # signed as another tag
        beta = BETA / "citronos-4.0.9-beta.1"
        with self.assertRaises(golden_update.UpdateRefused):         # a stable machine takes no beta build
            golden_update.check_bundle(Path(str(beta) + ".tar.gz"), Path(str(beta) + ".manifest.json").read_bytes(),
                                       Path(str(beta) + ".manifest.json.sig").read_bytes(), "4.0.1", channel="stable")

    def test_5_the_genuine_release_installs(self):
        SEEN_AUTH.clear()
        GITHUB_AUTH.clear()
        outcome, events = self.apply()
        self.assertEqual(outcome, "updated", [e for e in events if e[0] in ("error", "notice")])
        version = installed_version()
        self.assertEqual((version["version"], version["channel"], version["tag"]), ("4.0.2", "stable", "v4.0.2"))
        self.assertTrue(SEEN_AUTH, "the files came from the storage host")
        self.assertEqual(set(GITHUB_AUTH), {f"Bearer {TOKEN}"}, "GitHub was asked with the token")
        self.assertEqual(set(SEEN_AUTH), {None}, "the token stayed with GitHub")
        self.assertFalse(golden_update.check()["available"], "4.0.2 is now the newest")

    def test_6_install_local_wants_a_signature(self):
        bundle = WORK / "mine.tar.gz"
        shutil.copy(GOOD / "citronos-4.0.2.tar.gz", bundle)
        env = {k: v for k, v in os.environ.items()}
        proc = subprocess.run([sys.executable, str(ROOT / "apps/settings/golden_update.py"), "install-local",
                               "--from", str(bundle), "--root", str(WORK / "nowhere")],
                              capture_output=True, text=True, env=env, timeout=60)
        # (The mounted system doesn't exist, so --unsigned would stop there.)
        self.assertNotEqual(proc.returncode, 0)
        target = WORK / "disk"
        (target / "usr/share/golden-gate").mkdir(parents=True, exist_ok=True)
        (target / "etc").mkdir(exist_ok=True)
        (target / "etc/passwd").write_text("root:x:0:0::/root:/bin/bash\n")
        proc = subprocess.run([sys.executable, str(ROOT / "apps/settings/golden_update.py"), "install-local",
                               "--from", str(bundle), "--root", str(target)],
                              capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertIn("isn't a signed CitronOS release", proc.stdout)
        tampered = WORK / "citronos-4.0.3.tar.gz"
        for f in TAMPERED.iterdir():
            shutil.copy(f, WORK / f.name)
        proc = subprocess.run([sys.executable, str(ROOT / "apps/settings/golden_update.py"), "install-local",
                               "--from", str(tampered), "--root", str(target)],
                              capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn("isn't the one CitronOS signed", proc.stdout)

    def test_7_manifest_says_what_it_signs(self):
        info = json.loads((GOOD / "citronos-4.0.2.manifest.json").read_text())
        digest = hashlib.sha256((GOOD / "citronos-4.0.2.tar.gz").read_bytes()).hexdigest()
        self.assertEqual((info["format"], info["version"], info["tag"], info["channel"], info["sha256"]),
                         (1, "4.0.2", "v4.0.2", "stable", digest))

    def test_8_make_release_refuses_untrusted_keys_and_wrong_versions(self):
        out = WORK / "refused"
        for version, key, channel in (("4.0.6", OTHER, "stable"),          # a key systems don't trust
                                      ("5.0.0", TRUSTED, "stable"),        # not what Release.qml says
                                      ("4.0.7-rc.1", TRUSTED, "stable")):  # a pre-release on stable
            proc = subprocess.run(["bash", str(ROOT / "scripts/make-release.sh"), version, str(key), str(out), channel],
                                  capture_output=True, text=True, env={**os.environ, "GG_RELEASE_KEYS": str(KEYS)})
            self.assertNotEqual(proc.returncode, 0, version)
        self.assertFalse(out.exists() and any(out.iterdir()), "nothing was written")

if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        shutil.rmtree(WORK, ignore_errors=True)
