#!/usr/bin/env python3
"""Touch ID on a laptop's fingerprint reader (fprintd), as on the Mac:
Settings › Touch ID & Password adds and removes fingers; the lock screen
unlocks with one beside the password (its own PAM service, only
pam_fprintd); and, if chosen, sudo and system password prompts ask for a
finger first (touchid-helper.py, one marked line, the password still
working). Turned off, the PAM files are exactly as they were."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/settings/touchid-helper.py"
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


SUDO = "#%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n"
POLKIT = ("#%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\n"
          "password   include      system-auth\nsession    include      system-auth\n")


def helper(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(HELPER), *args], env=dict(os.environ, GG_TOUCHID_ROOT=str(root)),
                          capture_output=True, text=True, timeout=30)


with tempfile.TemporaryDirectory() as t:
    root = Path(t)
    pam = root / "etc/pam.d"
    pam.mkdir(parents=True)
    (pam / "sudo").write_text(SUDO)
    (pam / "polkit-1").write_text(POLKIT)
    os.chmod(pam / "sudo", 0o644)

    p = helper(root, "enable")
    check(p.returncode != 0 and "fprintd" in p.stderr, f"without fprintd it's refused ({p.stderr.strip()})")
    check((pam / "sudo").read_text() == SUDO, "…and nothing is changed")

    (root / "usr/lib/security").mkdir(parents=True)
    (root / "usr/lib/security/pam_fprintd.so").write_text("")
    check(json.loads(helper(root, "status").stdout) == {"admin": False, "reader": True}, "status: off, with the module")
    p = helper(root, "enable")
    check(p.returncode == 0 and json.loads(p.stdout)["admin"], f"turned on ({p.stderr.strip()})")
    for name, original in (("sudo", SUDO), ("polkit-1", POLKIT)):
        text = (pam / name).read_text()
        auth = [l for l in text.splitlines() if l.split() and l.split()[0] == "auth"]
        check(auth and "pam_fprintd.so" in auth[0] and "sufficient" in auth[0], f"{name}: a finger is asked for first: {auth}")
        check(any("system-auth" in l for l in auth[1:]), f"{name}: the password still works after it")
        check(text.startswith("#%PAM-1.0"), f"{name}: the header stays first")
    check(oct((pam / "sudo").stat().st_mode & 0o777) == "0o644", "the file keeps its mode")
    helper(root, "enable")
    check((pam / "sudo").read_text().count("pam_fprintd") == 1, "turned on twice, the line is there once")
    p = helper(root, "disable")
    check(p.returncode == 0 and not json.loads(p.stdout)["admin"], "turned off")
    check((pam / "sudo").read_text() == SUDO and (pam / "polkit-1").read_text() == POLKIT, "turned off, the files are exactly as they were")

    # A file that would no longer ask for a password is left alone.
    (pam / "sudo").write_text("#%PAM-1.0\naccount include system-auth\n")
    p = helper(root, "enable")
    check(p.returncode != 0 and "password" in p.stderr, f"a file without a password check isn't touched ({p.stderr.strip()})")

# The lock screen's own PAM service: a finger only, never a password.
service = (ROOT / "distro/archiso/overlay/etc/pam.d/gg-touchid").read_text()
auth = [l for l in service.splitlines() if l.split() and l.split()[0] == "auth"]
check(len(auth) == 1 and "pam_fprintd.so" in auth[0], f"gg-touchid asks only for a finger: {auth}")
lock = (ROOT / "shell/LockScreen.qml").read_text()
check('config: "gg-touchid"' in lock and 'config: "login"' in lock, "the lock screen listens for a finger beside the password")
check("fprintd-list" in lock and "Prefs.touchIdUnlock" in lock, "…only with a finger enrolled and Unlock with Touch ID on")
check("touch.abort()" in lock, "…and stops listening once unlocked")

# Packaging: fprintd, the PAM service and the helper's polkit action.
check(re.search(r"^fprintd$", (ROOT / "distro/archiso/packages.x86_64").read_text(), re.M) is not None, "fprintd is installed")
policy = (ROOT / "distro/archiso/overlay/usr/share/polkit-1/actions/org.goldengate.touchid.policy").read_text()
check("/usr/share/golden-gate/apps/settings/touchid-helper.py" in policy, "the polkit action names the helper")
check(os.access(HELPER, os.X_OK), "the helper is executable (pkexec runs it)")
install = (ROOT / "scripts/install.sh").read_text()
check("etc/pam.d/gg-touchid" in install and "org.goldengate.touchid.policy" in install, "install.sh installs both")

# Settings: the pane, with a reader and a finger (the preview's fprintd-list).
settings = (ROOT / "apps/settings.qml").read_text()
check('"touchid", "Touch ID & Password"' in settings, "Settings has Touch ID & Password")
r = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "app", "apps/settings.qml",
                    "--env", "GG_SETTINGS_PANE=touchid", "--wait", "1200", "--require-object", "touchIdFingers",
                    "-o", str(Path(tempfile.gettempdir()) / "touchid-pane.png")],
                   cwd=ROOT, capture_output=True, text=True, timeout=200,
                   env=dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen")))
check(r.returncode == 0, f"the pane shows the reader's fingers: {r.stderr.strip()[-400:]}")
check("TypeError" not in r.stderr and "ReferenceError" not in r.stderr, f"…without script errors: {r.stderr.strip()[-400:]}")

for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print("Touch ID: fingers added in Settings; the lock screen unlocks with one; sudo and system prompts ask for one when chosen, the password still working; off, PAM as it was")
sys.exit(1 if failures else 0)
