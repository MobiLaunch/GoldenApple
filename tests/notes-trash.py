#!/usr/bin/env python3
"""Notes' Recently Deleted (apps/notes/trash.py): deleting never replaces a
note already deleted (same title, or the same title from another folder);
Recover puts each back in the folder it came from, as "Title 2.md" if that
name has been taken since; Delete Immediately works only in Recently Deleted.
Deletes made at once keep every origin, an origin that can't be recorded
undoes its delete, and renaming a note (to follow its title) never replaces
another."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TRASH = Path(__file__).resolve().parents[1] / "apps/notes/trash.py"


class NotesTrash(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for folder in ("Notes", "Work"):
            (self.root / folder).mkdir()
        self.bin = self.root / "Recently Deleted"

    def tearDown(self):
        self.tmp.cleanup()

    def run_trash(self, command, path):
        p = subprocess.run([sys.executable, str(TRASH), command, str(self.root), str(path)], capture_output=True, text=True)
        return json.loads(p.stdout)

    def note(self, folder, name, text):
        path = self.root / folder / name
        path.write_text(text)
        return path

    def test_deleting_never_replaces(self):
        old = self.note("Notes", "Plan.md", "OLD DELETED")
        self.assertTrue(self.run_trash("delete", old)["ok"])
        new = self.note("Notes", "Plan.md", "NEW")
        r = self.run_trash("delete", new)
        self.assertTrue(r["ok"])
        self.assertEqual(Path(r["path"]).name, "Plan 2.md")
        work = self.note("Work", "Plan.md", "WORK")
        self.assertEqual(Path(self.run_trash("delete", work)["path"]).name, "Plan 3.md")
        self.assertEqual(sorted(p.read_text() for p in self.bin.glob("*.md")), ["NEW", "OLD DELETED", "WORK"])
        self.assertFalse(old.exists() or work.exists())

    def test_recover_goes_back_where_it_was(self):
        a = self.note("Notes", "Plan.md", "from Notes")
        b = self.note("Work", "Plan.md", "from Work")
        self.run_trash("delete", a)
        self.run_trash("delete", b)
        r = self.run_trash("recover", self.bin / "Plan 2.md")
        self.assertTrue(r["ok"], r)
        self.assertEqual(Path(r["path"]), b, "back in Work, under its own name")
        self.assertEqual(b.read_text(), "from Work")
        self.note("Notes", "Plan.md", "a new plan")
        r = self.run_trash("recover", self.bin / "Plan.md")
        self.assertEqual(Path(r["path"]).name, "Plan 2.md", "a note written since keeps its name")
        self.assertEqual((self.root / "Notes/Plan.md").read_text(), "a new plan")
        self.assertEqual((self.root / "Notes/Plan 2.md").read_text(), "from Notes")
        self.assertEqual(list(self.bin.glob("*.md")), [])

    def test_recover_into_a_folder_since_deleted(self):
        p = self.note("Work", "Idea.md", "idea")
        self.run_trash("delete", p)
        (self.root / "Work").rmdir()
        self.assertEqual(Path(self.run_trash("recover", self.bin / "Idea.md")["path"]), p)

    def test_delete_immediately(self):
        p = self.note("Notes", "Gone.md", "x")
        self.assertFalse(self.run_trash("erase", p)["ok"], "only from Recently Deleted")
        self.assertTrue(p.exists())
        self.run_trash("delete", p)
        self.assertTrue(self.run_trash("erase", self.bin / "Gone.md")["ok"])
        self.assertEqual(list(self.bin.glob("*.md")), [])

    def test_refuses_what_isnt_a_note(self):
        outside = Path(tempfile.mkdtemp()) / "x.md"
        outside.write_text("x")
        self.assertFalse(self.run_trash("delete", outside)["ok"])
        self.assertTrue(outside.exists())
        self.assertFalse(self.run_trash("delete", self.root / "Notes/missing.md")["ok"])

    def test_broken_origins_are_kept(self):
        self.bin.mkdir()
        (self.bin / ".origins.json").write_text("{not json")
        p = self.note("Work", "A.md", "a")
        self.assertTrue(self.run_trash("delete", p)["ok"])
        self.assertEqual((self.bin / ".origins.broken.json").read_text(), "{not json")
        self.assertEqual(Path(self.run_trash("recover", self.bin / "A.md")["path"]), p)

    def test_deletes_at_once_keep_every_origin(self):
        from concurrent.futures import ThreadPoolExecutor
        folders = [f"F{i}" for i in range(8)]
        notes = []
        for f in folders:
            (self.root / f).mkdir()
            notes.append(self.note(f, "Plan.md", f"from {f}"))
        with ThreadPoolExecutor(8) as pool:
            results = list(pool.map(lambda p: self.run_trash("delete", p), notes))
        self.assertTrue(all(r["ok"] for r in results), results)
        origins = json.loads((self.bin / ".origins.json").read_text())
        self.assertEqual(len(origins), 8, "every note's origin kept")
        for r in results:
            back = Path(self.run_trash("recover", r["path"])["path"])
            self.assertEqual(back.read_text(), "from " + back.parent.name, "each back in its own folder")

    def test_a_lost_origin_undoes_the_delete(self):
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location("notes_trash", TRASH)
        trash = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(trash)
        p = self.note("Work", "Kept.md", "kept")
        with patch.object(trash, "save_origins", side_effect=OSError(28, "No space left on device")), \
                patch("builtins.print"):
            self.assertEqual(trash.main(["trash.py", "delete", str(self.root), str(p)]), 1)
        self.assertEqual(p.read_text(), "kept", "still where it was")
        self.assertEqual(list(self.bin.glob("*.md")), [], "no copy left in Recently Deleted")

    def test_rename_never_replaces(self):
        a = self.note("Notes", "Draft.md", "draft")
        self.note("Notes", "Plan.md", "someone else's plan")
        r = subprocess.run([sys.executable, str(TRASH), "rename", str(self.root), str(a), "Plan.md"],
                           capture_output=True, text=True)
        self.assertEqual(Path(json.loads(r.stdout)["path"]).name, "Plan 2.md")
        self.assertEqual((self.root / "Notes/Plan.md").read_text(), "someone else's plan")
        self.assertEqual((self.root / "Notes/Plan 2.md").read_text(), "draft")
        self.assertFalse(a.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
