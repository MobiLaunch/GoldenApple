#!/usr/bin/env python3
"""Music playlist contracts: existing M3U, atomic changes, safety and conflicts."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "apps/music/playlists.py"


class Playlists(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.music = Path(self.temp.name) / "My Music"
        self.music.mkdir()
        self.lists = self.music / "Playlists"
        self.lists.mkdir()
        self.song = self.music / "Track One.mp3"
        self.song.write_bytes(b"audio")
        self.song2 = self.music / "Track Two.mp3"
        self.song2.write_bytes(b"audio")
        self.env = {**os.environ, "GG_MUSIC_DIR":str(self.music)}

    def call(self, cmd, data=None):
        p = subprocess.run([sys.executable,str(SCRIPT),cmd], input=json.dumps(data or {}),
                           capture_output=True,text=True,env=self.env,timeout=12)
        self.assertTrue(p.stdout.strip(), p.stderr)
        obj=json.loads(p.stdout)
        self.assertEqual(p.returncode,0 if obj["ok"] else 1,obj)
        return obj

    def test_create_add_reorder_remove_and_delete_recovery(self):
        created=self.call("create",{"name":"Road Trip"})
        self.assertTrue(created["ok"],created)
        p=Path(created["playlist"])
        self.assertEqual(p.parent,self.lists)
        self.assertEqual(p.stat().st_mode & 0o777,0o600)
        listed=created["playlists"][0]
        first=self.call("add",{"path":str(p),"expected":listed["revision"],"track":str(self.song)})
        self.assertTrue(first["ok"],first)
        second=self.call("add",{"path":str(p),"expected":first["playlists"][0]["revision"],"track":str(self.song2)})
        self.assertTrue(second["ok"],second)
        self.assertEqual(second["playlists"][0]["paths"],[str(self.song),str(self.song2)])
        moved=self.call("move",{"path":str(p),"expected":second["playlists"][0]["revision"],"index":1,"to":0})
        self.assertTrue(moved["ok"],moved)
        self.assertEqual(moved["playlists"][0]["paths"],[str(self.song2),str(self.song)])
        self.assertTrue((self.lists / "Road Trip.m3u8.bak").is_file())
        removed=self.call("remove",{"path":str(p),"expected":moved["playlists"][0]["revision"],"index":1})
        self.assertTrue(removed["ok"],removed)
        self.assertEqual(removed["playlists"][0]["paths"],[str(self.song2)])
        gone=self.call("delete",{"path":str(p),"expected":removed["playlists"][0]["revision"]})
        self.assertTrue(gone["ok"],gone)
        self.assertEqual(gone["playlists"],[])
        self.assertFalse(p.exists())
        self.assertEqual(len(list((self.lists / ".Deleted").glob("Road Trip.m3u8.*.bak"))),1)
        self.assertTrue(self.song.is_file())
        self.assertTrue(self.song2.is_file())

    def test_existing_m3u_extinf_and_relative_paths(self):
        p=self.lists/"Old Collection.m3u"
        p.write_text("#EXTM3U\n#EXTINF:181,Artist - First\n../Track One.mp3\n#EXTINF:200,Artist - Second\n../Track Two.mp3\n")
        listed=self.call("list")["playlists"][0]
        self.assertEqual(listed["paths"],[str(self.song),str(self.song2)])
        moved=self.call("move",{"path":str(p),"expected":listed["revision"],"index":1,"to":0})
        self.assertTrue(moved["ok"],moved)
        self.assertLess(p.read_text().index("#EXTINF:200"),p.read_text().index("#EXTINF:181"))
        self.assertIn("../Track One.mp3",p.read_text())
        self.assertTrue((self.lists/"Old Collection.m3u.bak").is_file())

    def test_stale_revisions_do_not_clobber(self):
        created=self.call("create",{"name":"Favorites"})
        path=created["playlist"]
        old=created["playlists"][0]["revision"]
        newer=self.call("add",{"path":path,"expected":old,"track":str(self.song)})
        self.assertTrue(newer["ok"])
        result=self.call("add",{"path":path,"expected":old,"track":str(self.song2)})
        self.assertFalse(result["ok"])
        self.assertIn("another window",result["error"])
        self.assertEqual(self.call("list")["playlists"][0]["paths"],[str(self.song)])

    def test_no_escape_symlinks_or_overwrites(self):
        for bad in ("../escape","absolute/name","trailing.","bad:name","", ".hidden", "invalid\nname"):
            result=self.call("create",{"name":bad})
            self.assertFalse(result["ok"],bad)
        created=self.call("create",{"name":"Mix"})
        self.assertTrue(created["ok"])
        self.assertFalse(self.call("create",{"name":"mix"})["ok"])
        outside=Path(self.temp.name)/"outside.m3u8"
        outside.write_text(str(self.song)+"\n")
        link=self.lists/"Outside.m3u8"
        link.symlink_to(outside)
        self.assertFalse(self.call("remove",{"path":str(link),"index":0})["ok"])
        self.assertEqual(outside.read_text(),str(self.song)+"\n")
        self.assertFalse(self.call("delete",{"path":str(outside)})["ok"])
        self.assertFalse(self.call("add",{"path":created["playlist"],"track":"not-an-absolute-file"})["ok"])

    def test_rename_duplicate_and_keep_songs(self):
        made=self.call("create",{"name":"Morning"})
        original=made["playlist"]
        renamed=self.call("rename",{"path":original,"name":"Evening","expected":made["playlists"][0]["revision"]})
        self.assertTrue(renamed["ok"],renamed)
        self.assertFalse(Path(original).exists())
        dupe=self.call("duplicate",{"path":renamed["playlist"],"expected":renamed["playlists"][0]["revision"]})
        self.assertTrue(dupe["ok"],dupe)
        self.assertEqual(len(dupe["playlists"]),2)
        self.assertEqual([p["name"] for p in dupe["playlists"]],["Evening","Evening Copy"])


    def test_recently_deleted_lists_restore_byte_exact_and_preserves_tracks(self):
        made = self.call("create", {"name":"Keep My Playlist"})
        p = Path(made["playlist"])
        original = "#EXTM3U\n#EXTINF:134,A band - Unique Song\n../Track One.mp3\n"
        p.write_text(original, encoding="utf-8")
        deleted = self.call("delete", {"path":str(p)})
        self.assertTrue(deleted["ok"], deleted)
        self.assertEqual(len(deleted["deleted"]), 1)
        item = self.call("deleted")["deleted"][0]
        self.assertEqual(item["name"], "Keep My Playlist")
        self.assertEqual(item["filename"], "Keep My Playlist.m3u8")
        self.assertGreater(item["deletedAt"], 0)
        restored = self.call("restore", {"path":item["path"], "expected":item["revision"]})
        self.assertTrue(restored["ok"], restored)
        self.assertEqual(Path(restored["playlist"]).read_text(), original)
        self.assertEqual(restored["deleted"], [])
        self.assertEqual(restored["playlists"][0]["paths"], [str(self.song)])
        self.assertTrue(self.song.exists())

    def test_restore_conflict_uses_safe_name_and_does_not_overwrite(self):
        created = self.call("create", {"name":"Play Me"})
        self.call("delete", {"path":created["playlist"]})
        deleted = self.call("deleted")["deleted"][0]
        original = self.call("create", {"name":"Play Me"})
        original_bytes = Path(original["playlist"]).read_bytes()
        revived = self.call("restore", {"path":deleted["path"], "expected":deleted["revision"]})
        self.assertTrue(revived["ok"], revived)
        self.assertEqual(Path(original["playlist"]).read_bytes(), original_bytes)
        self.assertEqual(Path(revived["playlist"]).name, "Play Me Restored.m3u8")
        self.assertEqual(len(revived["playlists"]), 2)
        self.assertEqual(self.call("deleted")["deleted"], [])

    def test_restore_rejects_stale_edits_and_unsafe_archives(self):
        made = self.call("create", {"name":"Protected"})
        self.call("delete", {"path":made["playlist"]})
        item = self.call("deleted")["deleted"][0]
        changed = self.call("restore", {"path":item["path"], "expected":"wrong"})
        self.assertFalse(changed["ok"])
        self.assertTrue(Path(item["path"]).exists())
        outside = Path(self.temp.name)/"dangerous.m3u8.1234567890123456789.bak"
        outside.write_text("#EXTM3U\n")
        self.assertFalse(self.call("restore", {"path":str(outside), "expected":"x"})["ok"])
        link = self.lists/".Deleted"/"Fake.m3u8.1234567890123456789.bak"
        link.symlink_to(outside)
        self.assertFalse(self.call("restore", {"path":str(link), "expected":"x"})["ok"])
        self.assertEqual(outside.read_text(), "#EXTM3U\n")

    def test_backup_symlink_is_not_followed_and_second_backup_is_kept(self):
        created = self.call("create", {"name":"Backup Safe"})
        playlist = Path(created["playlist"])
        external = Path(self.temp.name)/"outside.txt"
        external.write_text("do not touch")
        backup = playlist.with_name(playlist.name + ".bak")
        backup.symlink_to(external)
        first = self.call("add", {
            "path":str(playlist), "expected":created["playlists"][0]["revision"],
            "track":str(self.song)})
        self.assertTrue(first["ok"], first)
        second = self.call("add", {
            "path":str(playlist), "expected":first["playlists"][0]["revision"],
            "track":str(self.song2)})
        self.assertTrue(second["ok"], second)
        self.assertEqual(external.read_text(), "do not touch")
        backups = list(self.lists.glob("Backup Safe.m3u8.*.bak"))
        self.assertEqual(len(backups), 2)
        self.assertEqual(len({p.name for p in backups}), 2)
        self.assertTrue(all(p.is_file() for p in backups))

    def test_symlinked_deleted_directory_blocks_deletion(self):
        created = self.call("create", {"name":"Stay"})
        external = Path(self.temp.name)/"target"
        external.mkdir()
        (self.lists/".Deleted").symlink_to(external, target_is_directory=True)
        response = self.call("delete", {"path":created["playlist"]})
        self.assertFalse(response["ok"])
        self.assertTrue(Path(created["playlist"]).is_file())
        self.assertEqual(list(external.iterdir()), [])
        self.assertFalse(self.call("deleted")["ok"])


    def test_external_filesystem_without_hardlinks_still_creates_exclusively(self):
        import errno
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location("playlist_backend", SCRIPT)
        backend = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(backend)
        source = Path(self.temp.name) / "source.m3u8"
        target = Path(self.temp.name) / "target.m3u8"
        source.write_text("#EXTM3U\n../Track One.mp3\n")
        with patch.object(backend.os, "link", side_effect=OSError(errno.EOPNOTSUPP, "hardlinks unavailable")):
            backend.publish_exclusively(source, target)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                backend.publish_exclusively(source, target)
        self.assertEqual(source.read_text(), target.read_text())



if __name__ == "__main__":
    unittest.main(verbosity=2)
