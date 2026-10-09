#!/usr/bin/env python3
"""Real filesystem transfer, collision, cancellation, Undo and view-state checks."""
import errno
import json
import itertools
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/files"))
import operations as ops
import helper


class Workflow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.src = self.home / "source"; self.src.mkdir()
        self.dst = self.home / "destination"; self.dst.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "config"))

    def tearDown(self):
        self.tmp.cleanup()

    def transfer(self, paths, mode="copy", policy="keep-both", emit=None, controls=None):
        t = ops.Transfer(dict(paths=[str(p) for p in paths], destination=str(self.dst), mode=mode, conflicts=policy),
                         emit or (lambda e: None), controls)
        return t, t.run()

    def command(self, name, *args, data=None):
        r = subprocess.run([sys.executable, str(ROOT / "apps/files/helper.py"), name, *map(str,args)],
                           input=json.dumps(data or {}), capture_output=True, text=True, env=self.env, timeout=10)
        return json.loads(r.stdout)

    def test_mixed_copy_preserves_links_and_nested_selection(self):
        folder = self.src / "Project"; folder.mkdir()
        (folder / "notes.txt").write_text("notes")
        (folder / "broken link").symlink_to("missing")
        f = self.src / "name # with\nnewline.txt"; f.write_text("file")
        _, r = self.transfer([folder, folder / "notes.txt", f])
        self.assertTrue(r["ok"], r)
        self.assertEqual(len(r["completed"]), 2)
        self.assertEqual((self.dst / "Project/notes.txt").read_text(), "notes")
        self.assertEqual(os.readlink(self.dst / "Project/broken link"), "missing")
        self.assertEqual((self.dst / f.name).read_text(), "file")
        self.assertTrue((folder / "notes.txt").exists())

    def test_interactive_conflict_keep_both(self):
        f = self.src / "plan.txt"; f.write_text("new")
        (self.dst / f.name).write_text("existing")
        q = queue.Queue(); q.put(dict(answer="keep-both", all=True))
        events=[]
        _, r = self.transfer([f], policy="ask", controls=q, emit=events.append)
        self.assertTrue(r["ok"], r)
        self.assertTrue(any(e["event"]=="conflict" for e in events))
        self.assertEqual((self.dst / "plan.txt").read_text(), "existing")
        self.assertEqual((self.dst / "plan 2.txt").read_text(), "new")

    def test_skip_and_same_disk_move(self):
        a=self.src/"a"; a.write_text("A")
        b=self.src/"b"; b.write_text("B")
        (self.dst/"a").write_text("existing")
        _,r=self.transfer([a,b],mode="move",policy="skip")
        self.assertEqual(r["skipped"],[str(a)])
        self.assertTrue(a.exists()); self.assertFalse(b.exists())
        self.assertEqual((self.dst/"a").read_text(),"existing")
        self.assertEqual((self.dst/"b").read_text(),"B")
        self.assertEqual(r["completed"][0]["action"],"move")

    def test_cancel_keeps_completed_items_and_cleans_partial_copy(self):
        a=self.src/"first"; a.write_bytes(b"first")
        b=self.src/"large"; b.write_bytes(b"x"*(4*1024*1024))
        t=ops.Transfer(dict(paths=[str(a),str(b)],destination=str(self.dst),mode="copy",conflicts="keep-both"),lambda e:None)
        def emit(e):
            if e["event"]=="progress" and e.get("bytes",0)>len(b"first"):
                t.cancelled.set()
        t.emit=emit
        with patch.object(ops.time, "monotonic", side_effect=itertools.count(0, .2)):
            r=t.run()
        self.assertTrue(r["cancelled"])
        self.assertEqual((self.dst/"first").read_bytes(),b"first")
        self.assertFalse((self.dst/"large").exists())
        self.assertTrue(a.exists() and b.exists())
        self.assertEqual([p.name for p in self.dst.iterdir()],["first"])

    def test_source_change_discards_staged_copy(self):
        f=self.src/"changing"; f.write_bytes(b"x"*(2*1024*1024))
        changed=False
        def emit(e):
            nonlocal changed
            if e["event"]=="progress" and e.get("bytes",0)>0 and not changed:
                changed=True; f.write_text("newer content")
        with patch.object(ops.time, "monotonic", side_effect=itertools.count(0, .2)):
            _,r=self.transfer([f],emit=emit)
        self.assertFalse(r["ok"])
        self.assertEqual(f.read_text(),"newer content")
        self.assertEqual(list(self.dst.iterdir()),[])

    def test_cross_disk_move_and_publication_race(self):
        f=self.src/"a.txt"; f.write_text("source")
        real=ops.rename_noreplace
        race=True
        def rename(src,dst):
            nonlocal race
            if src==f: raise OSError(errno.EXDEV,"Cross-device link")
            if race:
                race=False; dst.write_text("raced item")
            return real(src,dst)
        with patch.object(ops,"rename_noreplace",rename):
            _,r=self.transfer([f],mode="move")
        self.assertTrue(r["ok"],r)
        self.assertFalse(f.exists())
        self.assertEqual((self.dst/"a.txt").read_text(),"raced item")
        self.assertEqual((self.dst/"a 2.txt").read_text(),"source")

    def test_duplicate_and_self_transfer(self):
        f=self.src/"draft.txt"; f.write_text("draft")
        _,r=self.transfer([f],mode="duplicate")
        self.assertEqual((self.src/"draft 2.txt").read_text(),"draft")
        t=ops.Transfer(dict(paths=[str(self.src)],destination=str(self.src),mode="copy"),lambda e:None)
        r=t.run(); self.assertFalse(r["ok"])

    def test_changed_cross_disk_source_keeps_both_copies(self):
        f=self.src/"changing"; f.write_text("original")
        real=ops.rename_noreplace
        def rename(src,dst):
            if src==f: raise OSError(errno.EXDEV,"Cross-device link")
            real(src,dst)
            f.write_text("new content")
        with patch.object(ops,"rename_noreplace",rename):
            _,r=self.transfer([f],mode="move")
        self.assertFalse(r["ok"])
        self.assertEqual(f.read_text(),"new content")
        self.assertEqual((self.dst/"changing").read_text(),"original")
        self.assertEqual(r["completed"][0]["action"],"copy")

    def test_live_protocol_cancel_at_conflict(self):
        f=self.src/"same"; f.write_text("original")
        (self.dst/"same").write_text("existing")
        p=subprocess.Popen([sys.executable,str(ROOT/"apps/files/operations.py")],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            p.stdin.write(json.dumps(dict(paths=[str(f)],destination=str(self.dst),mode="copy"))+"\n"); p.stdin.flush()
            while True:
                e=json.loads(p.stdout.readline())
                if e["event"]=="conflict": break
            p.stdin.write('{"cancel":true}\n'); p.stdin.flush()
            events=[]
            while True:
                line=p.stdout.readline()
                if not line: break
                events.append(json.loads(line))
            self.assertEqual(p.wait(timeout=10),0)
            self.assertTrue(events[-1]["cancelled"])
            self.assertEqual((self.dst/"same").read_text(),"existing")
            self.assertEqual(f.read_text(),"original")
        finally:
            if p.poll() is None: p.kill(); p.wait()
            p.stdin.close(); p.stdout.close()

    def test_undo_rename_collision_and_folder_contents(self):
        f=self.src/"old"; f.write_text("original")
        r=self.command("rename",f,"new")
        self.assertTrue(r["ok"])
        f.write_text("new item")
        refused=self.command("undo",data=r["undo"])
        self.assertFalse(refused["ok"])
        self.assertEqual(f.read_text(),"new item")
        self.assertEqual((self.src/"new").read_text(),"original")
        f.unlink()
        self.assertTrue(self.command("undo",data=r["undo"])["ok"])
        self.assertEqual(f.read_text(),"original")
        folder=self.command("mkdir",self.src,"Empty")
        self.assertTrue(self.command("undo",data=folder["undo"])["ok"])
        folder=self.command("mkdir",self.src,"Full")
        (self.src/"Full/keep").write_text("keep")
        self.assertFalse(self.command("undo",data=folder["undo"])["ok"])
        self.assertTrue((self.src/"Full/keep").exists())

    def test_folder_preferences_and_missing_volume_fallback(self):
        data=dict(lastPath=str(self.src),folders={str(self.src):dict(view="list",sortKey="size",descending=True)},showHidden=True)
        self.assertTrue(self.command("prefs-save",data=data)["ok"])
        self.assertEqual(self.command("prefs-load")["preferences"],data)
        self.assertEqual((self.home/"config/golden-gate/files.json").stat().st_mode & 0o777,0o600)
        data["lastPath"]=str(self.home/"removed-volume")
        self.command("prefs-save",data=data)
        r=self.command("prefs-load")
        self.assertEqual(r["preferences"]["lastPath"],str(self.home))
        self.assertIn("isn't available",r["warning"])

    def test_clipboard_cut_copy_and_uri_interoperability(self):
        bindir=self.home/"bin"; bindir.mkdir()
        clip=self.home/"clipboard.json"
        (bindir/"wl-copy").write_text('''#!/usr/bin/env python3
import sys,os,json
json.dump({"mime":sys.argv[-1],"text":sys.stdin.read()},open(os.environ["TEST_CLIP"],"w"))
''')
        (bindir/"wl-paste").write_text('''#!/usr/bin/env python3
import sys,os,json
d=json.load(open(os.environ["TEST_CLIP"]))
if d["mime"] != sys.argv[-1]: sys.exit(1)
sys.stdout.write(d["text"])
''')
        for p in bindir.iterdir(): p.chmod(0o755)
        self.env.update(PATH=str(bindir)+":"+os.environ["PATH"],TEST_CLIP=str(clip))
        f=self.src/"name # with\nnewline"; f.write_text("test")
        for mode in ("copy","cut"):
            self.assertTrue(self.command("clipboard-write",data=dict(mode=mode,paths=[str(f)]))["ok"])
            r=self.command("clipboard-read")
            self.assertEqual(r["paths"],[str(f)])
            self.assertEqual(r["mode"],"move" if mode=="cut" else "copy")
        clip.write_text(json.dumps(dict(mime="text/uri-list",text="# comment\nfile://remote.invalid/private\n"+f.as_uri()+"\r\n")))
        r=self.command("clipboard-read")
        self.assertEqual(r["paths"],[str(f)])
        self.assertEqual(r["mode"],"copy")

    def test_get_info_reports_the_entry_and_link(self):
        f=self.src/"note.txt"; f.write_text("hello")
        link=self.src/"link"; link.symlink_to("note.txt")
        info=self.command("info",link)["info"]
        self.assertEqual(info["path"],str(link))
        self.assertEqual(info["link"],"note.txt")
        self.assertTrue(info["permissions"].startswith("l"))


if __name__=="__main__":
    unittest.main(verbosity=2)
