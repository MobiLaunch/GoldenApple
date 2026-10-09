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


if __name__ == "__main__":
    unittest.main(verbosity=2)
