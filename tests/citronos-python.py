#!/usr/bin/env python3
"""The citronos Python package (T-2.4): atomic files, JSON-lines logs, child
processes, the keyring and the XDG folders. No keyring or network needed."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/lib/python"))
from citronos import files, jsonl, paths, proc, secrets  # noqa: E402


class Temp(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)


class Files(Temp):
    def test_a_new_file_is_private_and_whole(self):
        target = self.root / "a/b/store.json"
        files.atomic_write(target, "hello")
        self.assertEqual(target.read_text(), "hello")
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(sorted(p.name for p in target.parent.iterdir()), ["store.json"])

    def test_a_replaced_file_keeps_its_mode(self):
        target = self.root / "shared.txt"
        target.write_text("old")
        target.chmod(0o644)
        files.atomic_write(target, b"new")
        self.assertEqual(target.read_bytes(), b"new")
        self.assertEqual(target.stat().st_mode & 0o777, 0o644)

    def test_a_failed_write_leaves_the_old_file_and_no_temporary(self):
        target = self.root / "events.json"
        target.write_text("old")
        with patch.object(files.os, "replace", side_effect=OSError("disk full")), self.assertRaises(OSError):
            files.atomic_write(target, "new")
        self.assertEqual(target.read_text(), "old")
        self.assertEqual([p.name for p in self.root.iterdir()], ["events.json"])

    def test_backup_keeps_what_was_there(self):
        target, backup = self.root / "events.json", self.root / "events.backup.json"
        files.atomic_json(target, [1])
        files.atomic_json(target, [2], backup=backup)
        self.assertEqual(json.loads(target.read_text()), [2])
        self.assertEqual(json.loads(backup.read_text()), [1])

    def test_read_json(self):
        target = self.root / "prefs.json"
        self.assertEqual(files.read_json(target, default={}), {})
        target.write_text("[]")
        with self.assertRaises(ValueError):
            files.read_json(target, kind=dict)
        target.write_text("{not json")
        with self.assertRaises(ValueError):
            files.read_json(target)

    def test_keep_aside_never_overwrites(self):
        target = self.root / "events.json"
        target.write_text("damaged")
        first, second = files.keep_aside(target), files.keep_aside(target)
        self.assertNotEqual(first, second)
        self.assertEqual(first.read_text(), "damaged")
        self.assertEqual(second.read_text(), "damaged")
        self.assertTrue(first.name.startswith("events.broken-") and first.suffix == ".json")
        self.assertTrue(target.exists(), "the original stays for whoever looks")
        self.assertIsNone(files.keep_aside(self.root / "absent.json"))

    def test_locked_makes_writers_take_turns(self):
        lock = self.root / ".store.lock"
        holder = subprocess.Popen([sys.executable, "-c", textwrap.dedent(f"""
            import sys, time
            sys.path.insert(0, {str(ROOT / "apps/lib/python")!r})
            from citronos import files
            with files.locked({str(lock)!r}):
                print("held", flush=True)
                time.sleep(0.6)
            """)], stdout=subprocess.PIPE, text=True)
        self.assertEqual(holder.stdout.readline().strip(), "held")
        started = time.monotonic()
        with files.locked(lock):
            waited = time.monotonic() - started
        holder.wait()
        holder.stdout.close()
        self.assertGreater(waited, 0.3)


class Jsonl(Temp):
    def test_append_and_read(self):
        log = self.root / "history.jsonl"
        for i in range(3):
            jsonl.append(log, {"n": i, "text": "héllo"})
        self.assertEqual([r["n"] for r in jsonl.read(log)], [0, 1, 2])
        self.assertEqual([r["n"] for r in jsonl.read(log, limit=2)], [1, 2])
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)

    def test_a_torn_line_is_skipped_and_not_glued_to_the_next(self):
        log = self.root / "history.jsonl"
        jsonl.append(log, {"n": 1})
        with open(log, "ab") as out:
            out.write(b'{"n": 2, "cut sh')          # a crash mid-write
        jsonl.append(log, {"n": 3})
        self.assertEqual([r["n"] for r in jsonl.read(log)], [1, 3])

    def test_rewrite_prunes_at_once(self):
        log = self.root / "history.jsonl"
        for i in range(5):
            jsonl.append(log, {"n": i})
        jsonl.rewrite(log, jsonl.read(log)[-2:])
        self.assertEqual([r["n"] for r in jsonl.read(log)], [3, 4])

    def test_missing_log_is_empty(self):
        self.assertEqual(jsonl.read(self.root / "none.jsonl"), [])


class Proc(Temp):
    def test_run(self):
        r = proc.run([sys.executable, "-c", "import sys; print(sys.stdin.read().upper())"], timeout=10, input="hi")
        self.assertTrue(r.ok)
        self.assertEqual(r.stdout.strip(), "HI")

    def test_missing_timeout_and_no_shell(self):
        self.assertTrue(proc.run(["/nonexistent/tool"], timeout=1).missing)
        r = proc.run([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.3)
        self.assertTrue(r.timed_out)
        self.assertFalse(r.ok)
        with self.assertRaises(TypeError):
            proc.run("echo hi; rm -rf /", timeout=1)

    def test_a_child_dies_with_its_parent(self):
        pidfile = self.root / "child.pid"
        parent = subprocess.Popen([sys.executable, "-c", textwrap.dedent(f"""
            import subprocess, sys
            sys.path.insert(0, {str(ROOT / "apps/lib/python")!r})
            from citronos import proc
            child = subprocess.Popen(["sleep", "30"], preexec_fn=proc.die_with_parent)
            open({str(pidfile)!r}, "w").write(str(child.pid))
            child.wait()
            """)])
        for _ in range(50):
            if pidfile.exists() and pidfile.read_text():
                break
            time.sleep(0.05)
        child = int(pidfile.read_text())
        parent.send_signal(signal.SIGKILL)
        parent.wait()
        for _ in range(50):
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            os.kill(child, signal.SIGKILL)
            self.fail("the child outlived its parent")


FAKE_SECRET_TOOL = r'''#!/usr/bin/env python3
# A stand-in for secret-tool: items in a JSON file; every argv recorded.
import json, os, sys
store = os.environ["FAKE_KEYRING"]
items = json.load(open(store)) if os.path.exists(store) else []
open(store + ".argv", "a").write(json.dumps(sys.argv[1:]) + "\n")
cmd, args = sys.argv[1], [a for a in sys.argv[2:] if not a.startswith("--")]
label = next((a[8:] for a in sys.argv[2:] if a.startswith("--label=")), "")
attrs = dict(zip(args[::2], args[1::2]))
match = lambda i: all(i["attributes"].get(k) == v for k, v in attrs.items())
if cmd == "store":
    items = [i for i in items if not (i["attributes"] == attrs)] + [{"label": label, "attributes": attrs, "secret": sys.stdin.read()}]
elif cmd == "lookup":
    hit = next((i for i in items if match(i)), None)
    if not hit: sys.exit(1)
    sys.stdout.write(hit["secret"])
elif cmd == "clear":
    items = [i for i in items if not match(i)]
elif cmd == "search":
    for n, i in enumerate(i for i in items if match(i)):
        print(f"[/org/freedesktop/secrets/collection/login/{n}]")
        print(f"label = {i['label']}\nsecret = {i['secret']}\ncreated = 2026-10-26 10:00:00")
        print(f"[/org/freedesktop/secrets/collection/login/{n}]", file=sys.stderr)
        for k, v in i["attributes"].items(): print(f"attribute.{k} = {v}", file=sys.stderr)
json.dump(items, open(store, "w"))
'''


class Secrets(Temp):
    def setUp(self):
        super().setUp()
        bin_ = self.root / "bin"
        bin_.mkdir()
        tool = bin_ / "secret-tool"
        tool.write_text(FAKE_SECRET_TOOL)
        tool.chmod(0o755)
        self.store = self.root / "keyring.json"
        env = patch.dict(os.environ, {"PATH": f"{bin_}:{os.environ['PATH']}", "FAKE_KEYRING": str(self.store)})
        env.start()
        self.addCleanup(env.stop)

    def test_store_lookup_search_clear(self):
        secrets.store("CitronOS Mail", "hunter2", service="golden-gate-mail", account="me@example.com")
        secrets.store("CitronOS Mail", "other", service="golden-gate-mail", account="you@example.com")
        self.assertEqual(secrets.lookup(service="golden-gate-mail", account="me@example.com"), "hunter2")
        found = secrets.search(service="golden-gate-mail")
        self.assertEqual(sorted(i["attributes"]["account"] for i in found), ["me@example.com", "you@example.com"])
        self.assertEqual({i["secret"] for i in found}, {"hunter2", "other"})
        secrets.clear(service="golden-gate-mail", account="me@example.com")
        self.assertEqual(secrets.lookup(service="golden-gate-mail", account="me@example.com"), "")

    def test_a_secret_never_appears_in_arguments(self):
        secrets.store("Label", "s3cret-value", service="x", account="y")
        argv = (self.root / "keyring.json.argv").read_text()
        self.assertNotIn("s3cret-value", argv)

    def test_errors_say_what_happened(self):
        with patch.dict(os.environ, {"PATH": "/nonexistent"}), self.assertRaises(secrets.SecretError) as err:
            secrets.lookup(service="x", account="y")
        self.assertEqual(err.exception.code, "missing")
        slow = self.root / "bin/secret-tool"
        slow.write_text("#!/bin/sh\nsleep 5\n")
        with self.assertRaises(secrets.SecretError) as err:
            secrets.lookup(timeout=0.3, service="x", account="y")
        self.assertEqual(err.exception.code, "timeout")
        with self.assertRaises(ValueError):
            secrets.lookup()
        with self.assertRaises(ValueError):
            secrets.store("Label", "", service="x")


class Paths(unittest.TestCase):
    def test_xdg_folders(self):
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": "/tmp/cfg", "XDG_DATA_HOME": "relative/ignored", "HOME": "/home/u"}):
            self.assertEqual(paths.config("notes.json"), Path("/tmp/cfg/golden-gate/notes.json"))
            self.assertEqual(paths.data(), Path.home() / ".local/share/golden-gate")
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/nonexistent-run"}):
            self.assertIsNone(paths.runtime_dir())


if __name__ == "__main__":
    unittest.main()
