#!/usr/bin/env python3
"""The desktop's services as systemd user units (CS2-006, T-1.6).

hyprland.conf starts gg-session-start, which imports the session's display
into the user manager and starts citronos-session.target: the shell, AirDrop
and the icon resolver. The shell is restarted a second after it stops; five
stops in a minute start safe mode instead (GG_SAFE=1: no desktop widgets,
Citron or live window captures, and a notification saying so). gg-session
stops the target when Hyprland exits. Without a systemd user manager,
gg-session-start keeps the shell running itself, as the old line in
hyprland.conf did: on a new account (no ~/.local/state) too, with a big log
set aside as .old.
"""
import configparser
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
UNITS = ROOT / "distro/systemd/user"
START = ROOT / "compositor/hyprland/session-start.sh"
HYPR = (ROOT / "compositor/hyprland/hyprland.conf").read_text()


def unit(name):
    c = configparser.ConfigParser(strict=False, interpolation=None)
    c.optionxform = str
    c.read(UNITS / name)
    return c


class Units(unittest.TestCase):
    def test_the_shell_restarts_then_falls_back_to_safe_mode(self):
        shell = unit("citronos-shell.service")
        self.assertEqual(shell["Unit"]["PartOf"], "citronos-session.target")
        self.assertEqual(shell["Unit"]["StartLimitIntervalSec"], "60")
        self.assertEqual(shell["Unit"]["StartLimitBurst"], "5")
        self.assertEqual(shell["Unit"]["OnFailure"], "citronos-shell-safe.service")
        self.assertEqual(shell["Service"]["ExecStart"], "/usr/bin/env qs -c golden-gate")
        self.assertEqual(shell["Service"]["Restart"], "always")
        self.assertEqual(shell["Service"]["RestartSec"], "1")
        self.assertEqual(shell["Service"]["StandardOutput"], "journal")

    def test_safe_mode_is_the_same_shell_with_less(self):
        safe = unit("citronos-shell-safe.service")
        self.assertEqual(safe["Service"]["Environment"], "GG_SAFE=1")
        self.assertEqual(safe["Service"]["ExecStart"], unit("citronos-shell.service")["Service"]["ExecStart"])
        self.assertEqual(safe["Unit"]["Conflicts"], "citronos-shell.service")
        self.assertNotIn("OnFailure", safe["Unit"], "safe mode never starts itself again in a loop")
        self.assertEqual(safe["Service"]["Restart"], "on-failure")

    def test_the_session_target(self):
        target = unit("citronos-session.target")
        self.assertEqual(target["Unit"]["BindsTo"], "graphical-session.target")
        wants = " ".join(v for k, v in target.items("Unit") if k == "Wants").split()
        for service in ("citronos-shell.service", "citronos-airdrop.service", "citronos-icon-resolver.service"):
            self.assertIn(service, wants)
            self.assertEqual(unit(service)["Unit"]["PartOf"], "citronos-session.target")
            self.assertEqual(unit(service)["Service"]["StandardOutput"], "journal")
        self.assertEqual(unit("citronos-airdrop.service")["Service"]["ExecStart"], "/usr/bin/env gg-airdrop --serve")
        # "already running" (exit 0, the window started one) isn't restarted every few seconds.
        self.assertEqual(unit("citronos-airdrop.service")["Service"]["Restart"], "on-failure")
        self.assertIn('--serve ]; then exec python3 "$dir/airdropd.py" serve',
                      (ROOT / "apps/airdrop/share.sh").read_text())

    def test_hyprland_starts_the_session_not_loops(self):
        self.assertIn("\nexec-once = gg-session-start\n", HYPR)
        for gone in ("while :", "airdropd.py serve", "gg-icon-resolver watch", "golden-gate-shell.log"):
            self.assertNotIn(gone, HYPR)

    def test_installed(self):
        install = (ROOT / "scripts/install.sh").read_text()
        self.assertEqual(install.count('session-start.sh" "$BIN/gg-session-start"'), 2, "extras and the main install")
        self.assertIn('"$R/usr/lib/systemd/user/${unit##*/}"', install)
        self.assertIn('UNITS="$ROOT/usr/lib/systemd/user"; else UNITS="$CONF/systemd/user"', install)
        self.assertIn('["/usr/local/bin/gg-session-start"]="0:0:755"', (ROOT / "distro/archiso/build.sh").read_text())


def stubs(tmp: Path, systemd: bool):
    (tmp / "bin").mkdir()
    (tmp / "home").mkdir()
    calls = tmp / "calls"
    (tmp / "bin/systemctl").write_text(
        "#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + str(calls) + "\n"
        + ("exit 0\n" if systemd else "exit 1\n"))
    (tmp / "bin/qs").write_text("#!/bin/sh\necho shell ran\n")         # a shell that stops at once
    (tmp / "bin/logger").write_text("#!/bin/sh\n:\n")
    (tmp / "bin/gg-lock").write_text("#!/bin/sh\nprintf 'lock %s\\n' \"$*\" >> " + str(calls) + "\nsleep 1\n")
    for f in (tmp / "bin").iterdir():
        f.chmod(0o755)
    return calls


class SessionStart(unittest.TestCase):
    def test_imports_the_display_then_restarts_the_target(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            calls = stubs(tmp, systemd=True)
            env = dict(os.environ, HOME=str(tmp / "home"), PATH=f"{tmp / 'bin'}:/usr/bin:/bin",
                       WAYLAND_DISPLAY="wayland-1", HYPRLAND_INSTANCE_SIGNATURE="abc")
            p = subprocess.run(["sh", str(START)], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(p.returncode, 0, p.stderr)
            lines = calls.read_text().splitlines()
            imported = next(i for i, l in enumerate(lines) if l.startswith("--user import-environment"))
            for var in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_DATA_DIRS", "PATH"):
                self.assertIn(var, lines[imported].split())
            self.assertIn("--user reset-failed citronos-*", lines)
            self.assertEqual(lines[-1], "--user restart citronos-session.target")
            self.assertLess(imported, len(lines) - 1, "the display is imported before the units start")
            self.assertFalse((tmp / "home/.local/state/golden-gate-shell.log").exists())

    def fallback(self, seconds, big_log=False):
        tmp = Path(tempfile.mkdtemp())
        stubs(tmp, systemd=False)
        log = tmp / "home/.local/state/golden-gate-shell.log"
        if big_log:
            log.parent.mkdir(parents=True)
            log.write_bytes(b"\0" * 4_100_000)
        # Its own process group: the lock screen's loop runs beside the shell's.
        p = subprocess.Popen(["sh", str(START)], start_new_session=True,
                             env=dict(os.environ, HOME=str(tmp / "home"), PATH=f"{tmp / 'bin'}:/usr/bin:/bin"))
        time.sleep(seconds)
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        self.calls = (tmp / "calls").read_text().splitlines() if (tmp / "calls").exists() else []
        return log

    def test_without_systemd_on_a_new_account(self):
        log = self.fallback(3)
        self.assertTrue(log.exists(), "the shell started, its log made")
        self.assertGreaterEqual(log.read_text().count("shell ran"), 2, "and was started again after stopping")
        self.assertIn("lock serve", self.calls, "and the lock screen, in a process of its own")

    def test_without_systemd_a_big_log_is_set_aside(self):
        log = self.fallback(1, big_log=True)
        self.assertEqual((log.parent / "golden-gate-shell.log.old").stat().st_size, 4_100_000)
        self.assertLess(log.stat().st_size, 1000)


class Logout(unittest.TestCase):
    def test_gg_session_stops_the_target_when_hyprland_exits(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            calls = stubs(tmp, systemd=True)
            (tmp / "bin/Hyprland").write_text("#!/bin/sh\nexit 0\n")
            (tmp / "bin/Hyprland").chmod(0o755)
            env = dict(os.environ, HOME=str(tmp / "home"), PATH=f"{tmp / 'bin'}:/usr/bin:/bin",
                       XDG_RUNTIME_DIR=str(tmp))
            subprocess.run(["sh", str(ROOT / "distro/archiso/overlay/usr/local/bin/gg-session")],
                           env=env, capture_output=True, text=True, timeout=20)
            lines = calls.read_text().splitlines()
            self.assertIn("--user stop citronos-session.target", lines)
            self.assertIn("--user unset-environment WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE", lines)


DRIVER = r'''
import json, sys
sys.path.insert(0, sys.argv.pop(1))
out = sys.argv.pop(1)
import preview as P
ran = []
log = P.Preview.log
def logged(self, text):
    ran.append(text)
    log(self, text)
P.Preview.log = P.Slot(str)(logged)
def ipc(self, target, function, args):
    from PySide6.QtGui import QGuiApplication
    open(out, "w").write(json.dumps({"ran": ran, "windows": [w.title() for w in QGuiApplication.topLevelWindows() if w.isVisible()]}))
P.Preview.ipc = ipc
sys.exit(P.main())
'''


class SafeMode(unittest.TestCase):
    def shell(self, safe):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t)
            (t / "driver.py").write_text(DRIVER)
            out = t / "state.json"
            args = [sys.executable, str(t / "driver.py"), str(ROOT / "tools/preview"), str(out), "shell",
                    "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--size", "1440x900",
                    "--wait", "3600", "--do", "x.y", "-o", str(t / "shot.png")]
            if safe:
                args[5:5] = ["--env", "GG_SAFE=1"]
            p = subprocess.run(args, env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
                               capture_output=True, text=True, timeout=240)
            self.assertTrue(out.exists(), p.stderr[-3000:])
            return json.loads(out.read_text())

    def test_safe_mode_says_so(self):
        s = self.shell(safe=True)
        notes = [json.loads(l[5:]) for l in s["ran"] if l.startswith("exec ") and '"notify-send"' in l]
        self.assertTrue(any("safe mode" in " ".join(n) for n in notes), s["ran"][-20:])

    def test_a_normal_start_doesnt(self):
        s = self.shell(safe=False)
        self.assertTrue(any('"desktop ready"' in l for l in s["ran"]), "the shell came up")
        self.assertFalse(any("safe mode" in l for l in s["ran"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
