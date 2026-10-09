#!/usr/bin/env python3
"""Offline checks for approved Golden Gate / GPL WhiteSur application icons."""
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "icons/icon-resolver.py"
SVG = b'<svg xmlns="http://www.w3.org/2000/svg"><rect x="0" y="0" width="100" height="100"/></svg>'
EMBEDDED = b'<svg xmlns="http://www.w3.org/2000/svg"><image href="data:image/png;base64,iVBORw0KGgo="/></svg>'


def archive():
    buffer = io.BytesIO()
    with tarfile.open(mode="w:gz", fileobj=buffer) as tf:
        def file(path, data):
            ti = tarfile.TarInfo("WhiteSur-icon-theme-2026-09-10/" + path)
            ti.size = len(data)
            tf.addfile(ti, io.BytesIO(data))
        file("COPYING", b"                    GNU GENERAL PUBLIC LICENSE\n"
             b"                       Version 3, 29 June 2007\n")
        file("src/apps/scalable/firefox.svg", EMBEDDED)
        file("src/apps/scalable/steam.svg", SVG)
        file("src/apps/scalable/evil.svg",
             b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
        alias = tarfile.TarInfo("WhiteSur-icon-theme-2026-09-10/links/apps/scalable/org.mozilla.firefox.svg")
        alias.type = tarfile.SYMTYPE
        alias.linkname = "../../../src/apps/scalable/firefox.svg"
        tf.addfile(alias)
    return buffer.getvalue()


class MemoryResponse:
    def __init__(self, blob):
        self.io = io.BytesIO(blob)
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def read(self, size):
        return self.io.read(size)


class ResolverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {
            "HOME": str(base),
            "XDG_DATA_HOME": str(base / "data"),
            "XDG_CACHE_HOME": str(base / "cache"),
            "XDG_DATA_DIRS": str(base / "system"),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        spec = importlib.util.spec_from_file_location("gg_icon_resolver_test", SCRIPT)
        self.resolver = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.resolver)
        self.apps = base / "data/applications"
        self.apps.mkdir(parents=True)
        self.theme = base / "data/icons/GoldenGate/scalable/apps"
        self.theme.mkdir(parents=True)
        (self.theme / "system-file-manager.svg").write_bytes(SVG)
        (self.apps / "org.goldengate.Files.desktop").write_text(
            "[Desktop Entry]\nName=Files\nType=Application\nExec=gg-files\nIcon=system-file-manager\n")
        (self.apps / "org.mozilla.firefox.desktop").write_text(
            "[Desktop Entry]\nName=Firefox\nType=Application\nExec=firefox\nIcon=org.mozilla.firefox\n")
        (self.apps / "org.example.Unknown.desktop").write_text(
            "[Desktop Entry]\nName=Unknown\nType=Application\nExec=unknown\nIcon=application-x-executable\n")

    def test_safe_icons_and_gpl_source(self):
        self.assertTrue(self.resolver.safe_art(SVG))
        self.assertTrue(self.resolver.safe_art(EMBEDDED))
        self.assertFalse(self.resolver.safe_art(b'<svg><script>alert(1)</script></svg>'))
        self.assertFalse(self.resolver.safe_art(b'<svg><image href="https://bad.example/x.png"/></svg>'))
        with patch.object(self.resolver.urllib.request, "urlopen",
                          return_value=MemoryResponse(archive())):
            self.resolver.bootstrap()
        idx = self.resolver.pack_index()
        self.assertIn("org.mozilla.firefox", idx)
        self.assertIn("firefox", idx)
        self.assertNotIn("evil", idx)
        self.assertTrue(self.resolver.LICENSE_PATH.is_file())
        self.assertTrue((self.resolver.SOURCES / "svg/org.mozilla.firefox.svg").is_file())

    def test_only_real_approved_art_appears_in_manifest(self):
        with patch.object(self.resolver.urllib.request, "urlopen",
                          return_value=MemoryResponse(archive())):
            self.resolver.bootstrap()
        result = self.resolver.sync()
        self.assertIn("org.goldengate.Files", result)
        self.assertIn("org.mozilla.firefox", result)
        self.assertNotIn("org.example.Unknown", result)
        self.assertEqual(result["org.mozilla.firefox"]["source"], "WhiteSur")
        stored = json.loads(self.resolver.MANIFEST.read_text())
        self.assertEqual(stored["version"], 1)
        self.assertEqual(stored["apps"], result)
        # An update changes the manifest when its icon becomes available.
        (self.apps / "org.example.Unknown.desktop").write_text(
            "[Desktop Entry]\nName=Unknown\nType=Application\nExec=unknown\nIcon=steam\n")
        updated = self.resolver.sync()
        self.assertIn("org.example.Unknown", updated)
        # Remove an installed desktop file: it must disappear again.
        (self.apps / "org.example.Unknown.desktop").unlink()
        result = self.resolver.sync()
        self.assertNotIn("org.example.Unknown", result)

    def test_hidden_and_generic_apps_never_leak(self):
        (self.apps / "org.example.Secret.desktop").write_text(
            "[Desktop Entry]\nName=Secret\nType=Application\nExec=secret\n"
            "NoDisplay=true\nIcon=system-file-manager\n")
        res = self.resolver.sync()
        self.assertNotIn("org.example.Secret", res)
        self.assertNotIn("org.example.Unknown", res)

    def test_store_hooks_and_filtered_launcher(self):
        launch = (ROOT / "shell/Applications.qml").read_text()
        dock = (ROOT / "shell/Dock.qml").read_text()
        install = (ROOT / "scripts/install.sh").read_text()
        store = (ROOT / "apps/software/helper.py").read_text()
        hypr = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
        self.assertIn("hasApprovedIcon(e)", launch)
        self.assertIn("!hasApprovedIcon(e)", launch)
        self.assertNotIn('name: "Other"', launch)
        self.assertIn("launchpad-icons.json", launch)
        self.assertIn("launchpad-icons.json", dock)
        self.assertIn('["gg-icon-resolver", "bootstrap"', store)
        self.assertIn("gg-icon-resolver watch", hypr)
        self.assertIn('icon-resolver.py', install)
        self.assertIn('gg-icon-resolver', install)


if __name__ == "__main__":
    unittest.main(verbosity=2)
