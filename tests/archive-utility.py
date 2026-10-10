#!/usr/bin/env python3
"""Archive Utility regression tests; run without Quickshell or real user files."""
from __future__ import annotations

import io
import json
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/archive/helper.py"


def call(*args):
    result = subprocess.run([sys.executable, str(HELPER), *map(str, args)],
                            capture_output=True, text=True, timeout=25)
    events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    return result.returncode, (events[-1] if events else {}), events


class ArchiveUtility(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gg-archive-test-")
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)

    def test_zip_create_list_extract_round_trip(self):
        source = self.folder / "My folder"
        source.mkdir()
        (source / "with spaces.txt").write_text("Golden Gate\n" * 25)
        (source / "subfolder").mkdir()
        (source / "subfolder/notes.md").write_text("Hello")
        code, outcome, events = call("create", source)
        self.assertEqual(code, 0, events)
        self.assertEqual(outcome["mode"], "create")
        archive = Path(outcome["destination"])
        self.assertTrue(archive.exists())
        code, listing, _ = call("inspect", archive)
        self.assertEqual(code, 0)
        self.assertEqual(listing["count"], 4)
        self.assertTrue(any(x["name"].endswith("with spaces.txt") for x in listing["entries"]))
        code, extracted, events = call("extract", archive)
        self.assertEqual(code, 0, events)
        dest = Path(extracted["destination"])
        self.assertEqual((dest / "My folder" / "subfolder" / "notes.md").read_text(), "Hello")
        self.assertEqual((dest / "My folder" / "with spaces.txt").read_text(), "Golden Gate\n" * 25)
        # Extraction never destroys an existing folder.
        code, second, _ = call("extract", archive)
        self.assertEqual(code, 0)
        self.assertNotEqual(second["destination"], extracted["destination"])
        self.assertTrue(dest.exists())

    def test_tar_and_gz_are_visible_and_extractable(self):
        for fmt in ("w", "w:gz", "w:bz2", "w:xz"):
            suffix = {"w": ".tar", "w:gz": ".tar.gz",
                      "w:bz2": ".tar.bz2", "w:xz": ".tar.xz"}[fmt]
            archive = self.folder / ("example" + suffix)
            with tarfile.open(archive, fmt) as t:
                data = b"safe archive data"
                entry = tarfile.TarInfo("docs/readme.txt")
                entry.size = len(data)
                t.addfile(entry, io.BytesIO(data))
            c, info, _ = call("inspect", archive)
            self.assertEqual(c, 0, (suffix, info))
            self.assertEqual(info["count"], 1)
            c, out, _ = call("extract", archive)
            self.assertEqual(c, 0, (suffix, out))
            self.assertEqual((Path(out["destination"]) / "docs/readme.txt").read_bytes(), data)

    def test_reject_zip_path_traversal_and_leave_no_output(self):
        for name in ("../outside.txt", "/tmp/escape.txt", "C:\\Windows\\escape.txt",
                     "folder\\..\\outside.txt"):
            archive = self.folder / "unsafe.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr("safe.txt", "okay")
                z.writestr(name, "unsafe")
            code, out, _ = call("extract", archive)
            self.assertNotEqual(code, 0, name)
            self.assertFalse(out.get("ok"), name)
            self.assertFalse((self.folder / "unsafe" / "safe.txt").exists())
            self.assertFalse(any(x.name.startswith(".gg-extract-") for x in self.folder.iterdir()))

    def test_reject_zip_symlink(self):
        archive = self.folder / "symlink.zip"
        with zipfile.ZipFile(archive, "w") as z:
            entry = zipfile.ZipInfo("evil-link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(entry, "/etc/passwd")
        code, out, _ = call("extract", archive)
        self.assertNotEqual(code, 0)
        self.assertIn("link", out.get("error", "").lower())

    def test_reject_tar_links(self):
        archive = self.folder / "unsafe.tar"
        with tarfile.open(archive, "w") as t:
            entry = tarfile.TarInfo("example")
            entry.type = tarfile.SYMTYPE
            entry.linkname = "../../outside"
            t.addfile(entry)
        code, out, _ = call("extract", archive)
        self.assertNotEqual(code, 0)
        self.assertIn("link", out.get("error", "").lower())

    def test_duplicate_entries_are_rejected(self):
        archive = self.folder / "duplicates.zip"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("README", "1")
            z.writestr("readme", "2")
        code, out, _ = call("extract", archive)
        self.assertNotEqual(code, 0)
        self.assertIn("duplicate", out.get("error", "").lower())

    def test_existing_destination_is_preserved(self):
        archive = self.folder / "backup.zip"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("a.txt", "new")
        existing = self.folder / "backup"
        existing.mkdir()
        (existing / "a.txt").write_text("original")
        code, out, _ = call("extract", archive)
        self.assertEqual(code, 0)
        self.assertEqual((existing / "a.txt").read_text(), "original")
        self.assertEqual(Path(out["destination"]).name, "backup 2")

    def test_presentation_and_files_are_connected(self):
        files = (ROOT / "apps/files.qml").read_text()
        app = (ROOT / "apps/archive.qml").read_text()
        launcher = (ROOT / "apps/archive/open.sh").read_text()
        install = (ROOT / "scripts/install.sh").read_text()
        desktop = (ROOT / "apps/desktop/org.goldengate.ArchiveUtility.desktop").read_text()
        self.assertIn('Quickshell.execDetached(["gg-archive", entry.path])', files)
        self.assertIn('text: "Extract Here"', files)
        self.assertIn('"Compress to ZIP"', files)
        self.assertIn("archive/helper.py", app)
        self.assertIn("archiveMemberList", app)
        self.assertIn("FileDialog.OpenFiles", app)
        self.assertIn('GG_ARCHIVE_PATH=', launcher)
        self.assertGreaterEqual(install.count('> "$BIN/gg-archive"'), 2)
        self.assertIn("application/zip", desktop)
        self.assertIn("org.goldengate.ArchiveUtility.desktop", install)


if __name__ == "__main__":
    unittest.main(verbosity=2)
