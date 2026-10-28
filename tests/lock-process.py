#!/usr/bin/env python3
"""The lock screen as a process of its own (CS2-005, T-1.5).

lock-shell.qml runs LockScreen apart from the shell (citronos-lock.service,
`gg-lock serve`). gg-lock marks the session locked in $XDG_RUNTIME_DIR, then
asks the lock screen over IPC, or starts it; a lock screen that starts while
the mark is there locks at once (after a crash, with Hyprland keeping the
session locked meanwhile: misc:allow_session_lock_restore), and unlocking
removes the mark. The real lock-shell.qml runs in the preview harness;
gg-lock runs against stub qs and systemctl.
"""
from __future__ import annotations
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GG_LOCK = ROOT / "compositor/hyprland/lock.sh"

DRIVER = r'''
import json, sys
sys.path.insert(0, sys.argv.pop(1))
out = sys.argv.pop(1)
import preview as P
from PySide6.QtCore import QMetaObject, QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest
ran = []
log = P.Preview.log
def logged(self, text):
    ran.append(text)
    log(self, text)
P.Preview.log = P.Slot(str)(logged)
run = P.Preview.run
def recorded(self, cmd):
    ran.append("run " + json.dumps([str(c) for c in (cmd.toVariant() if hasattr(cmd, "toVariant") else cmd)]))
    return run(self, cmd)
P.Preview.run = P.Slot("QVariant", result="QVariantMap")(recorded)
ipc = P.Preview.ipc
def objects(name):
    return [o for w in QGuiApplication.topLevelWindows() for o in w.findChildren(QObject)
            if o.metaObject().className().split("_QML")[0] == name]
def step(self, target, function, args):
    if target == "test":
        locks = objects("WlSessionLock")
        if function == "refuse":      # the compositor ends the lock: Quickshell reports an unlock
            for l in locks:
                l.setProperty("locked", False)
            QTest.qWait(900)
        if function == "signin":      # the password was right: the lock surface says unlocked
            for s in objects("LockSurface"):
                QMetaObject.invokeMethod(s, "unlocked")
            QTest.qWait(900)
        open(out, "w").write(json.dumps({"ran": ran, "locked": [bool(l.property("locked")) for l in locks]}))
        return True
    return ipc(self, target, function, args)
P.Preview.ipc = step
sys.exit(P.main())
'''


def run_lock_screen(runtime: Path, *steps: str) -> dict:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "driver.py").write_text(DRIVER)
        out = t / "state.json"
        args = [sys.executable, str(t / "driver.py"), str(ROOT / "tools/preview"), str(out),
                "app", "shell/lock-shell.qml", "--env", f"XDG_RUNTIME_DIR={runtime}", "--wait", "700"]
        for s in steps:
            args += ["--do", s]
        p = subprocess.run(args + ["-o", str(t / "shot.png")], cwd=ROOT, capture_output=True, text=True,
                           timeout=180, env={**os.environ, "QT_QPA_PLATFORM": "offscreen"})
        bad = [l for l in p.stderr.splitlines() if ("LockScreen" in l or "lock-shell" in l) and "rror" in l]
        assert not bad, bad
        assert out.exists(), p.stderr[-2000:]
        return json.loads(out.read_text())


def execs(state, program, kind="exec"):
    n = len(kind) + 1
    return [json.loads(l[n:]) for l in state["ran"] if l.startswith(kind + " ") and json.loads(l[n:])[0] == program]


class LockScreenProcess(unittest.TestCase):
    def test_waits_unlocked_without_the_mark(self):
        with tempfile.TemporaryDirectory() as r:
            s = run_lock_screen(Path(r), "test.state")
            self.assertEqual(s["locked"], [False])
            self.assertEqual(execs(s, "touch"), [])

    def test_locks_at_once_when_started_with_the_mark(self):
        with tempfile.TemporaryDirectory() as r:
            (Path(r) / "citronos-locked").touch()
            s = run_lock_screen(Path(r), "test.state")
            self.assertEqual(s["locked"], [True], "a lock screen restarted while locked locks again")

    def test_lock_marks(self):
        with tempfile.TemporaryDirectory() as r:
            s = run_lock_screen(Path(r), "lock.lock", "test.state")
            self.assertEqual(s["locked"], [True])
            self.assertEqual(execs(s, "touch"), [["touch", f"{r}/citronos-locked"]])

    def test_signing_in_clears_the_mark_then_unlocks(self):
        with tempfile.TemporaryDirectory() as r:
            (Path(r) / "citronos-locked").touch()
            s = run_lock_screen(Path(r), "test.signin")
            self.assertEqual(s["locked"], [False])
            self.assertEqual(execs(s, "rm", "run"), [["rm", "-f", f"{r}/citronos-locked"]])
            self.assertEqual(execs(s, "rm"), [])

    def test_a_refused_lock_asks_again(self):
        # Started straight after a crash, while the compositor still counts the
        # dead lock screen's lock: refused, it asks again, and keeps the mark.
        with tempfile.TemporaryDirectory() as r:
            (Path(r) / "citronos-locked").touch()
            s = run_lock_screen(Path(r), "test.refuse")
            self.assertEqual(s["locked"], [True], "asked again while the mark is there")
            self.assertEqual(execs(s, "rm", "run") + execs(s, "rm"), [], "a refusal isn't a sign-in")
            self.assertTrue((Path(r) / "citronos-locked").exists())

    def test_asked_to_lock_it_holds_the_lock_until_signed_in(self):
        with tempfile.TemporaryDirectory() as r:
            s = run_lock_screen(Path(r), "lock.lock", "test.refuse")
            self.assertEqual(s["locked"], [True], "the compositor ended the lock: it asks again")
            s = run_lock_screen(Path(r), "lock.lock", "test.signin", "test.refuse")
            self.assertEqual(s["locked"], [False], "after signing in it lets go")


STUB = '''#!/bin/sh
printf '%s %s\\n' "${0##*/}" "$*" >> "$CALLS"
case "${0##*/}:$*" in
  qs:*ipc*) exit "${QS_IPC:-0}" ;;
  systemctl:*) exit "${SYSTEMCTL:-0}" ;;
esac
'''


class GgLock(unittest.TestCase):
    def run_gg_lock(self, *args, qs_ipc=0, systemctl=0):
        t = Path(tempfile.mkdtemp())
        (t / "bin").mkdir()
        for name in ("qs", "systemctl", "nohup"):
            (t / "bin" / name).write_text(STUB if name != "nohup" else '#!/bin/sh\nexec "$@"\n')
            (t / "bin" / name).chmod(0o755)
        env = {"PATH": f"{t / 'bin'}:/usr/bin:/bin", "HOME": str(t), "XDG_RUNTIME_DIR": str(t),
               "CALLS": str(t / "calls"), "QS_IPC": str(qs_ipc), "SYSTEMCTL": str(systemctl)}
        subprocess.run(["sh", str(GG_LOCK), *args], env=env, timeout=10, check=True)
        subprocess.run(["sleep", "0.2"])
        calls = (t / "calls").read_text().splitlines() if (t / "calls").exists() else []
        return t, calls

    def test_marks_then_asks_the_lock_screen(self):
        t, calls = self.run_gg_lock()
        self.assertTrue((t / "citronos-locked").exists())
        self.assertEqual(calls, [f"qs -p {t}/.config/quickshell/golden-gate/lock-shell.qml ipc call lock lock"])

    def test_starts_the_lock_screen_if_it_isnt_running(self):
        t, calls = self.run_gg_lock(qs_ipc=1)
        self.assertTrue((t / "citronos-locked").exists())
        self.assertEqual(calls[-1], "systemctl --user start citronos-lock.service")

    def test_without_systemd_it_runs_the_lock_screen_itself(self):
        t, calls = self.run_gg_lock(qs_ipc=1, systemctl=1)
        self.assertEqual(calls[-1], f"qs -p {t}/.config/quickshell/golden-gate/lock-shell.qml")

    def test_serve(self):
        t, calls = self.run_gg_lock("serve")
        self.assertEqual(calls, [f"qs -p {t}/.config/quickshell/golden-gate/lock-shell.qml"])
        self.assertFalse((t / "citronos-locked").exists(), "serving doesn't lock")


class Wiring(unittest.TestCase):
    def test_unit_always_comes_back(self):
        c = configparser.ConfigParser(strict=False, interpolation=None)
        c.optionxform = str
        c.read(ROOT / "distro/systemd/user/citronos-lock.service")
        self.assertEqual(c["Service"]["ExecStart"], "/usr/bin/env gg-lock serve")
        self.assertEqual(c["Service"]["Restart"], "always")
        self.assertEqual((c["Service"]["RestartSec"], c["Service"]["RestartMaxDelaySec"]), ("200ms", "5s"),
                         "back within a moment, and a lock screen that keeps failing backs off")
        self.assertEqual(c["Unit"]["StartLimitIntervalSec"], "0", "no start limit: it must come back while locked")
        self.assertEqual(c["Unit"]["PartOf"], "citronos-session.target")
        self.assertIn("citronos-lock.service", (ROOT / "distro/systemd/user/citronos-session.target").read_text())

    def test_no_crash_handler(self):
        """A crashed lock screen leaves no dump (a password being typed is in
        its memory), and nothing holds its lock open after it."""
        self.assertIn("export QS_DISABLE_CRASH_HANDLER=1\n", (ROOT / "compositor/hyprland/lock.sh").read_text())

    def test_hyprland_keeps_the_session_locked_for_it(self):
        self.assertIn("allow_session_lock_restore = true", (ROOT / "compositor/hyprland/hyprland.conf").read_text())

    def test_everything_locks_through_gg_lock(self):
        self.assertIn("    lock_cmd = gg-lock\n", (ROOT / "compositor/hyprland/hypridle.conf").read_text())
        sys.path.insert(0, str(ROOT / "compositor/hyprland"))
        import idle
        self.assertIn("    lock_cmd = gg-lock\n", idle.conf(idle.DEFAULTS))
        shell = (ROOT / "shell/shell.qml").read_text()
        self.assertNotIn('source: "LockScreen.qml"', shell, "the shell doesn't hold the lock itself")
        self.assertIn('function lock(): void { Quickshell.execDetached(["gg-lock"]) }', shell)

    def test_installed(self):
        install = (ROOT / "scripts/install.sh").read_text()
        self.assertEqual(install.count('lock.sh" "$BIN/gg-lock"'), 2)
        self.assertIn('["/usr/local/bin/gg-lock"]="0:0:755"', (ROOT / "distro/archiso/build.sh").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
