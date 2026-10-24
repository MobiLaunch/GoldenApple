#!/usr/bin/env python3
"""Files' backend (apps/files/helper.py) in a scratch home folder: drag and drop
moves within a disk and names clashes as Finder does ("name 2.txt"), copies
when asked, never moves a folder into itself; Move to Trash writes the
freedesktop .trashinfo, Put Back restores to where it was, Empty Trash empties
it; Recents lists what was opened (recently-used.xbel) and what changed lately.
Rename never replaces another item (a clash is refused, a case-only change
works) and renames a link itself, not what it points to."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "apps/files/helper.py"


class FilesHelper(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        for d in ("Documents", "Desktop", "Pictures"):
            (self.home / d).mkdir()
        (self.home / "Documents/plan.txt").write_text("plan")
        (self.home / "Documents/Project").mkdir()
        (self.home / "Documents/Project/notes.md").write_text("notes")
        (self.home / "Desktop/plan.txt").write_text("other plan")

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        env = {**os.environ, "HOME": str(self.home), "XDG_DATA_HOME": str(self.home / ".local/share")}
        p = subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, text=True, env=env)
        return json.loads(p.stdout)

    def test_rename_never_replaces(self):
        docs = self.home / "Documents"
        (docs / "draft.txt").write_text("draft")
        r = self.run_helper("rename", str(docs / "draft.txt"), "plan.txt")
        self.assertFalse(r["ok"])
        self.assertIn("already taken", r["error"])
        self.assertEqual((docs / "draft.txt").read_text(), "draft", "neither file disappears")
        self.assertEqual((docs / "plan.txt").read_text(), "plan")
        r = self.run_helper("rename", str(docs / "plan.txt"), "Project")
        self.assertFalse(r["ok"], "nor is a folder replaced")
        self.assertTrue((docs / "Project/notes.md").exists())
        (docs / "Empty").mkdir()
        r = self.run_helper("rename", str(docs / "Project"), "Empty")
        self.assertFalse(r["ok"], "not even an empty one")
        self.assertTrue((docs / "Project/notes.md").exists())
        r = self.run_helper("rename", str(docs / "draft.txt"), "final.txt")
        self.assertTrue(r["ok"])
        self.assertEqual((docs / "final.txt").read_text(), "draft")
        self.assertFalse((docs / "draft.txt").exists())

    def test_rename_case_and_odd_names(self):
        docs = self.home / "Documents"
        r = self.run_helper("rename", str(docs / "plan.txt"), "Plan.txt")
        self.assertTrue(r["ok"], r)
        self.assertEqual(sorted(p.name for p in docs.iterdir()), ["Plan.txt", "Project"])
        self.assertEqual((docs / "Plan.txt").read_text(), "plan")
        for bad in ("", "  ", ".", ".."):
            self.assertFalse(self.run_helper("rename", str(docs / "Plan.txt"), bad)["ok"], repr(bad))
        self.assertTrue(self.run_helper("rename", str(docs / "Plan.txt"), "Plan.txt")["ok"], "the same name is fine")
        self.assertTrue((docs / "Plan.txt").exists())
        self.assertFalse(self.run_helper("rename", str(docs / "gone.txt"), "x")["ok"])

    def test_rename_a_link_renames_the_link(self):
        docs = self.home / "Documents"
        (docs / "to-plan").symlink_to(docs / "plan.txt")
        r = self.run_helper("rename", str(docs / "to-plan"), "shortcut")
        self.assertTrue(r["ok"], r)
        self.assertTrue((docs / "plan.txt").exists(), "the target keeps its name")
        self.assertEqual(os.readlink(docs / "shortcut"), str(docs / "plan.txt"))
        self.assertFalse(os.path.lexists(docs / "to-plan"))
        (docs / "dangling").symlink_to(docs / "nowhere")
        r = self.run_helper("rename", str(docs / "dangling"), "still dangling")
        self.assertTrue(r["ok"], r)
        self.assertEqual(os.readlink(docs / "still dangling"), str(docs / "nowhere"))
        (docs / "to-project").symlink_to(docs / "Project")
        self.assertFalse(self.run_helper("rename", str(docs / "to-project"), "plan.txt")["ok"])
        self.assertTrue((docs / "Project/notes.md").exists())
        self.assertEqual((docs / "plan.txt").read_text(), "plan")

    def test_fallback_never_replaces_a_name_taken_mid_rename(self):
        """A disk without renameat2(RENAME_NOREPLACE): another item appearing
        under the new name while renaming is never replaced."""
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location("files_helper", HELPER)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        docs = self.home / "Documents"
        (docs / "a.txt").write_text("A")
        (docs / "dir").mkdir()
        (docs / "dir/in.txt").write_text("in")
        real_lstat = os.lstat
        unsupported = patch.object(helper, "RENAME_NOREPLACE", 1 << 30)    # EINVAL: as if unsupported

        def racing(target, content):
            def lstat(p, *a, **k):
                r = real_lstat(p, *a, **k)
                if not os.path.lexists(target):           # someone else takes the name just now
                    (target.mkdir() if content is None else target.write_text(content))
                return r
            return lstat
        with unsupported, patch.object(helper.os, "lstat", racing(docs / "b.txt", "B")):
            with self.assertRaises(FileExistsError):
                helper.rename_noreplace(docs / "a.txt", docs / "b.txt")
        self.assertEqual(((docs / "a.txt").read_text(), (docs / "b.txt").read_text()), ("A", "B"), "both kept")
        with unsupported, patch.object(helper.os, "lstat", racing(docs / "other", None)):
            with self.assertRaises(FileExistsError):
                helper.rename_noreplace(docs / "dir", docs / "other")
        self.assertTrue((docs / "dir/in.txt").exists())
        with unsupported:
            helper.rename_noreplace(docs / "a.txt", docs / "c.txt")
            helper.rename_noreplace(docs / "dir", docs / "dir2")
        self.assertEqual((docs / "c.txt").read_text(), "A")
        self.assertTrue((docs / "dir2/in.txt").exists() and not (docs / "dir").exists())
        # No hard links either (FAT through FUSE…): refused, nothing changed.
        with unsupported, patch.object(helper.os, "link", side_effect=PermissionError(1, "Operation not permitted")):
            with self.assertRaises(helper.RenameUnsafe):
                helper.rename_noreplace(docs / "c.txt", docs / "d.txt")
        self.assertTrue((docs / "c.txt").exists() and not (docs / "d.txt").exists())

    def test_new_folder_that_exists(self):
        r = self.run_helper("mkdir", str(self.home / "Documents"), "Project")
        self.assertFalse(r["ok"])
        self.assertIn("already taken", r["error"])
        self.assertTrue((self.home / "Documents/Project/notes.md").exists())

    def test_drop_moves_and_names_clashes(self):
        r = self.run_helper("drop", str(self.home / "Desktop"), "auto", str(self.home / "Documents/plan.txt"))
        self.assertTrue(r["ok"], r)
        self.assertFalse((self.home / "Documents/plan.txt").exists())
        self.assertEqual((self.home / "Desktop/plan 2.txt").read_text(), "plan")
        self.assertEqual((self.home / "Desktop/plan.txt").read_text(), "other plan")

    def test_drop_copy_keeps_the_original(self):
        r = self.run_helper("drop", str(self.home / "Pictures"), "copy", str(self.home / "Documents/Project"))
        self.assertTrue(r["ok"], r)
        self.assertTrue((self.home / "Documents/Project/notes.md").exists())
        self.assertEqual((self.home / "Pictures/Project/notes.md").read_text(), "notes")

    def test_drop_into_itself_is_refused(self):
        r = self.run_helper("drop", str(self.home / "Documents/Project"), "auto", str(self.home / "Documents"))
        self.assertFalse(r["ok"])
        self.assertTrue((self.home / "Documents/Project/notes.md").exists())

    def test_drop_where_it_already_is_does_nothing(self):
        r = self.run_helper("drop", str(self.home / "Documents"), "auto", str(self.home / "Documents/plan.txt"))
        self.assertTrue(r["ok"])
        self.assertEqual(sorted(p.name for p in (self.home / "Documents").iterdir()), ["Project", "plan.txt"])

    def test_trash_put_back_and_empty(self):
        doc = self.home / "Documents/plan.txt"
        self.assertTrue(self.run_helper("trash", str(doc))["ok"])
        self.assertFalse(doc.exists())
        listing = self.run_helper("list", "trash:")
        self.assertEqual([e["name"] for e in listing["entries"]], ["plan.txt"])
        entry = listing["entries"][0]
        self.assertEqual(entry["origin"], str(doc))
        self.assertGreater(entry["deleted"], 0)
        # The Dock opens the Trash folder by its path; that's the Trash too.
        by_path = self.run_helper("list", str(self.home / ".local/share/Trash/files"))
        self.assertEqual(by_path["path"], "trash:")
        # A second plan.txt in the Trash gets its own name; both come back.
        (self.home / "Documents/plan.txt").write_text("again")
        self.assertTrue(self.run_helper("trash", str(doc))["ok"])
        names = [e["trashName"] for e in self.run_helper("list", "trash:")["entries"]]
        self.assertEqual(len(set(names)), 2)
        self.assertTrue(self.run_helper("put-back", entry["trashName"])["ok"])
        self.assertEqual(doc.read_text(), "plan")
        self.assertTrue(self.run_helper("empty-trash")["ok"])
        self.assertEqual(self.run_helper("list", "trash:")["entries"], [])
        self.assertEqual(list((self.home / ".local/share/Trash/info").iterdir()), [])

    def test_recents(self):
        share = self.home / ".local/share"
        share.mkdir(parents=True)
        (share / "recently-used.xbel").write_text(
            '<?xml version="1.0"?><xbel version="1.0">'
            f'<bookmark href="file://{self.home}/Documents/Project/notes.md" added="2026-10-01T10:00:00Z" '
            'modified="2026-10-01T10:00:00Z" visited="2099-10-01T10:00:00Z"/>'
            '<bookmark href="file:///gone/file.txt" visited="2099-10-02T10:00:00Z"/></xbel>')
        r = self.run_helper("list", "recents:")
        names = [e["name"] for e in r["entries"]]
        self.assertEqual(r["path"], "recents:")
        self.assertEqual(names[0], "notes.md")          # opened most recently
        self.assertIn("plan.txt", names)                # changed lately
        self.assertNotIn("file.txt", names)             # no longer there
        self.assertNotIn("Project", names)              # files, not folders


if __name__ == "__main__":
    unittest.main(verbosity=1)
