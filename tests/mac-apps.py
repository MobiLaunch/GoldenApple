#!/usr/bin/env python3
"""Mac apps in the App Store (apps/software/macapps.py), end to end in a scratch
home folder, against a local web server standing in for developers' downloads:

- the catalog keeps installable apps (a .zip or .dmg with an .app) and drops
  .pkg installers, Apple-silicon-only casks and withdrawn ones, and prefers a
  cask's Intel download, since Darling translates Intel Mac code;
- install downloads, checks the developer's checksum, unpacks keeping the
  bundle's symlinks and executable bits, installs in ~/Applications, reads
  Info.plist, takes the icon out of the .icns, and adds a Launchpad entry;
- a download that doesn't match its checksum, or an Apple-silicon-only app,
  is refused and nothing is installed;
- a .dmg is opened with 7-Zip;
- open runs the app with Darling (via /Volumes/SystemRoot), and an app that
  quits with an error is reported as not having opened, with Darling's output;
- remove takes it all away again."""
from __future__ import annotations

import functools
import hashlib
import http.server
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/software/macapps.py"
PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 40 + b"IEND"


def macho(*cpus: int) -> bytes:
    """A Mach-O header: thin for one CPU, universal (fat) for several."""
    if len(cpus) == 1:
        return struct.pack("<II", 0xFEEDFACF, cpus[0]) + b"\0" * 64
    head = struct.pack(">II", 0xCAFEBABE, len(cpus))
    for c in cpus:
        head += struct.pack(">iiIII", c, 3, 4096, 4096, 12)
    return head + b"\0" * 64


def icns(png: bytes) -> bytes:
    chunk = b"ic09" + struct.pack(">I", 8 + len(png)) + png
    small = b"ic07" + struct.pack(">I", 8 + 12) + b"\x89PNG\r\n\x1a\n" + b"tiny"
    body = small + chunk
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


def bundle_zip(name: str, exe: bytes) -> bytes:
    """A zipped Name.app the way developers ship them: Info.plist, an
    executable, an icon, and a framework symlink."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        def add(path: str, data: bytes, mode: int = 0o644, link: bool = False):
            info = zipfile.ZipInfo(path)
            info.external_attr = ((stat.S_IFLNK if link else stat.S_IFREG) | mode) << 16
            z.writestr(info, data)
        plist = plistlib.dumps({"CFBundleExecutable": name, "CFBundleIdentifier": f"com.example.{name}",
                                "CFBundleShortVersionString": "2.1", "CFBundleIconFile": "AppIcon"})
        add(f"{name}.app/Contents/Info.plist", plist)
        add(f"{name}.app/Contents/MacOS/{name}", exe, 0o755)
        add(f"{name}.app/Contents/Resources/AppIcon.icns", icns(PNG))
        add(f"{name}.app/Contents/Frameworks/Kit.framework/Versions/A/Kit", b"lib", 0o755)
        add(f"{name}.app/Contents/Frameworks/Kit.framework/Kit", b"Versions/A/Kit", 0o777, link=True)
        add("__MACOSX/._junk", b"")
    return buf.getvalue()


class MacApps(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.www = Path(cls.tmp.name) / "www"
        cls.www.mkdir()
        files = {
            "Notepad.zip": bundle_zip("Notepad", macho(0x01000007, 0x0100000C)),   # universal
            "Silicon.zip": bundle_zip("Silicon", macho(0x0100000C)),              # Apple silicon only
            "Bad.zip": bundle_zip("Bad", macho(0x01000007)),
            "Disk.dmg": b"not really a disk image",
        }
        for name, data in files.items():
            (cls.www / name).write_bytes(data)
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass
        handler = functools.partial(Quiet, directory=str(cls.www))
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{cls.server.server_port}"
        sha = lambda n: hashlib.sha256(files[n]).hexdigest()
        app = lambda name: [{"app": [f"{name}.app"]}, {"zap": [{"trash": "~/Library/x"}]}]
        cls.casks = [
            {"token": "notepad", "name": ["Notepad"], "desc": "Write things down", "homepage": "https://notepad.example",
             "version": "2.1", "url": f"{base}/arm/Notepad.zip", "sha256": "0" * 64, "artifacts": app("Notepad"),
             "depends_on": {"macos": {">=": ["12"]}},
             # The Intel build, as Homebrew lists it: a variation without arm64_.
             # Homebrew now lists Linux builds too; those aren't Mac apps.
             "variations": {"x86_64_linux": {"url": f"{base}/notepad.tar.gz", "sha256": "1" * 64},
                            "sequoia": {"url": f"{base}/Notepad.zip", "sha256": sha("Notepad.zip")}}},
            {"token": "silicon", "name": ["Silicon"], "version": "1", "url": f"{base}/Silicon.zip",
             "sha256": sha("Silicon.zip"), "artifacts": app("Silicon")},
            {"token": "bad", "name": ["Bad"], "version": "1", "url": f"{base}/Bad.zip", "sha256": "f" * 64, "artifacts": app("Bad")},
            {"token": "disk", "name": ["Disk"], "version": "3", "url": f"{base}/Disk.dmg", "sha256": "no_check", "artifacts": app("Disk")},
            {"token": "installer", "name": ["Installer"], "version": "1", "url": f"{base}/x.pkg", "artifacts": [{"pkg": ["x.pkg"]}]},
            {"token": "armonly", "name": ["ArmOnly"], "version": "1", "url": f"{base}/a.zip", "artifacts": app("ArmOnly"),
             "depends_on": {"arch": [{"type": "arm", "bits": 64}]}},
            {"token": "gone", "name": ["Gone"], "version": "1", "url": f"{base}/g.zip", "artifacts": app("Gone"), "disabled": True},
        ]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.tmp.cleanup()

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(dir=self.tmp.name))
        self.bin = self.home / "bin"
        self.bin.mkdir()
        catalog = self.home / "cask.json"
        catalog.write_text(json.dumps(self.casks))
        self.env = {**os.environ, "HOME": str(self.home), "XDG_DATA_HOME": str(self.home / ".local/share"),
                    "XDG_CACHE_HOME": str(self.home / ".cache"), "GG_MAC_CATALOG_URL": catalog.as_uri(),
                    "PATH": f"{self.bin}:/usr/bin:/bin", "no_proxy": "127.0.0.1", "NO_PROXY": "127.0.0.1"}

    def run_helper(self, *args):
        p = subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, text=True, env=self.env, timeout=60)
        events = [json.loads(l) for l in p.stdout.splitlines() if l.startswith("{")]
        return p.returncode, events

    def tool(self, name, script):
        f = self.bin / name
        f.write_text("#!/bin/sh\n" + script)
        f.chmod(0o755)

    def test_catalog_keeps_installable_apps(self):
        code, events = self.run_helper("catalog")
        self.assertEqual(code, 0, events)
        apps = {a["token"]: a for a in events[-1]["apps"]}
        self.assertEqual(sorted(apps), ["bad", "disk", "notepad", "silicon"])
        self.assertTrue(apps["notepad"]["url"].endswith("/Notepad.zip"), "the Intel download")
        self.assertNotIn("/arm/", apps["notepad"]["url"])
        self.assertEqual(apps["notepad"]["minMacOS"], "12")
        self.assertEqual(apps["disk"]["kind"], "dmg")
        self.assertTrue(apps["notepad"]["checksum"])
        self.assertFalse(apps["disk"]["checksum"], "no_check: no published checksum")
        self.assertIn("iina", events[-1]["featured"])

    def test_install_open_remove(self):
        code, events = self.run_helper("install", "notepad")
        self.assertEqual(code, 0, events)
        self.assertTrue(any(e["event"] == "progress" and "Downloading" in e["message"] for e in events))
        app = self.home / "Applications/Notepad.app"
        exe = app / "Contents/MacOS/Notepad"
        self.assertTrue(os.access(exe, os.X_OK), "the executable keeps its executable bit")
        link = app / "Contents/Frameworks/Kit.framework/Kit"
        self.assertTrue(link.is_symlink() and os.readlink(link) == "Versions/A/Kit", "framework symlinks survive")
        self.assertFalse((self.home / "Applications/__MACOSX").exists())
        self.assertEqual(events[-1]["arch"], ["arm64", "x86_64"])
        icon = self.home / ".local/share/golden-gate/mac-icons/notepad.png"
        self.assertEqual(icon.read_bytes(), PNG, "the largest PNG from the .icns")
        desktop = (self.home / ".local/share/applications/gg-mac-notepad.desktop").read_text()
        self.assertIn("Exec=gg-mac-open notepad", desktop)
        self.assertIn(f"Icon={icon}", desktop)
        rec = self.run_helper("installed")[1][-1]["apps"]["notepad"]
        self.assertEqual(rec["version"], "2.1")
        self.assertEqual(rec["bundleId"], "com.example.Notepad")

        # Without Darling: say how to get it.
        code, events = self.run_helper("open", "notepad")
        self.assertEqual((code, events[-1]["code"]), (1, "no-darling"))
        # Darling runs the app from inside its view of the file system.
        self.tool("darling", f'echo "$@" > "{self.home}/darling-args"; sleep 30\n')
        p = subprocess.Popen([sys.executable, str(HELPER), "open", "notepad"], stdout=subprocess.PIPE, text=True, env=self.env)
        out, _ = p.communicate(timeout=30)
        self.assertEqual(p.returncode, 0, out)
        self.assertEqual((self.home / "darling-args").read_text().strip(), f"/Volumes/SystemRoot{exe}")
        self.assertTrue(self.run_helper("installed")[1][-1]["apps"]["notepad"]["opened"])
        # One that quits with an error didn't open: say so, with Darling's words.
        self.tool("darling", 'echo "dyld: Symbol not found: _NSAppearanceNameDarkAqua"; exit 1\n')
        code, events = self.run_helper("open", "notepad")
        self.assertEqual((code, events[-1]["code"]), (1, "didnt-open"))
        self.assertIn("Symbol not found", events[-1]["details"])
        self.assertFalse(self.run_helper("installed")[1][-1]["apps"]["notepad"]["opened"])

        self.assertEqual(self.run_helper("remove", "notepad")[0], 0)
        self.assertFalse(app.exists())
        self.assertFalse((self.home / ".local/share/applications/gg-mac-notepad.desktop").exists())
        self.assertEqual(self.run_helper("installed")[1][-1]["apps"], {})

    def test_wrong_checksum_is_refused(self):
        code, events = self.run_helper("install", "bad")
        self.assertEqual(code, 1)
        self.assertIn("checksum", events[-1]["message"])
        # Every failure says why, with the log's last lines and where the log is.
        self.assertIn("full log:", events[-1]["details"])
        self.assertTrue((self.home / ".cache/golden-gate/mac-logs/install-bad.log").exists())
        self.assertFalse((self.home / "Applications/Bad.app").exists())

    def test_apple_silicon_only_is_refused(self):
        code, events = self.run_helper("install", "silicon")
        self.assertEqual(code, 1)
        self.assertIn("Apple silicon", events[-1]["message"])
        self.assertFalse((self.home / "Applications/Silicon.app").exists())
        self.assertFalse((self.home / ".local/share/applications/gg-mac-silicon.desktop").exists())

    def test_zip_cant_write_outside_its_folder(self):
        sys.path.insert(0, str(HELPER.parent))
        import macapps
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            link = zipfile.ZipInfo("Evil.app/out")
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(link, str(self.home))
            z.writestr("Evil.app/out/planted", "gotcha")
        archive = self.home / "evil.zip"
        archive.write_bytes(buf.getvalue())
        dest = self.home / "unpack"
        dest.mkdir()
        with self.assertRaises(RuntimeError):
            macapps.extract_zip(archive, dest)
        self.assertFalse((self.home / "planted").exists())

    def without_7zip(self):
        """PATH as it is, less any 7-Zip the machine has (CI images now ship one)."""
        shadow = self.home / "no7z"
        shadow.mkdir(exist_ok=True)
        for d in ("/usr/bin", "/bin"):
            for f in Path(d).iterdir():
                if f.name not in ("7z", "7zz", "7za", "7zr") and not (shadow / f.name).exists():
                    (shadow / f.name).symlink_to(f)
        return f"{self.bin}:{shadow}"

    def test_dmg_opens_with_7zip(self):
        path = self.env["PATH"]
        self.env["PATH"] = self.without_7zip()
        code, events = self.run_helper("install", "disk")
        self.env["PATH"] = path
        self.assertEqual(code, 1)
        self.assertIn("7-Zip", events[-1]["message"], "says what's missing")
        # 7-Zip unpacks the image's volume, with the app inside it.
        src = self.home / "volume"
        with zipfile.ZipFile(io.BytesIO(bundle_zip("Disk", macho(0x01000007)))) as z:
            z.extractall(src / "Disk 3")
        # As real 7-Zip does with the image's "Applications" link to
        # /Applications: the app comes out whole, and it exits 2 anyway.
        self.tool("7z", f'for a; do case $a in -o*) out=${{a#-o}};; esac; done\ncp -a "{src}/." "$out/"\n'
                        'echo "ERROR: Dangerous link path was ignored : Disk 3/Applications : /Applications"\nexit 2\n')
        code, events = self.run_helper("install", "disk")
        self.assertEqual(code, 0, events)
        self.assertTrue(os.access(self.home / "Applications/Disk.app/Contents/MacOS/Disk", os.X_OK))
        self.assertTrue((self.home / "Applications/Disk.app/Contents/Info.plist").exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
