#!/usr/bin/env python3
"""Safety regression for the CitronOS graphical installer backend."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
helper = root / "apps" / "installer" / "helper.py"
source = helper.read_text(encoding="utf-8")

for needle in [
    'Path("/run/archiso")',
    "os.geteuid()",
    '"ERASE:" + device',
    "live_device()",
    'sys.argv[1] == "disks"',
    'sys.argv[1] == "install"',
    "release_device(device)",
    "wait_for_partitions(boot, root)",
    '"--info=progress2"',
    "boot_disk = live_device()",
    "golden_update.remove_live_leftovers(TARGET)",
    '"hooks/archiso" in listing',
]:
    if needle not in source:
        raise SystemExit(f"installer safety gate missing: {needle}")

with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    fakebin = td / "bin"
    fakebin.mkdir()
    lsblk = fakebin / "lsblk"
    lsblk.write_text(
        """#!/bin/sh
cat <<'JSON'
{"blockdevices":[
 {"path":"/dev/sda","model":"Internal","size":128000000000,"type":"disk","tran":"sata","rm":false},
 {"path":"/dev/sdb","model":"USB","size":64000000000,"type":"disk","tran":"usb","rm":true},
 {"path":"/dev/loop0","model":"Loop","size":64000000000,"type":"loop","tran":"","rm":false},
 {"path":"/dev/sdc","model":"Tiny","size":8000000000,"type":"disk","tran":"sata","rm":false}
]}
JSON
""",
        encoding="utf-8",
    )
    lsblk.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = str(fakebin) + os.pathsep + env.get("PATH", "")

    out = subprocess.check_output([sys.executable, str(helper), "disks"], text=True, env=env)
    rows = json.loads(out)
    if [r["path"] for r in rows] != ["/dev/sda"]:
        raise SystemExit(f"disk discovery safety filter failed: {rows!r}")

# Target preparation must actively release stale mounts/swap instead of
# relying on the destination already being idle.
if 'run(["swapoff", path], check=False)' not in source:
    raise SystemExit("installer no longer deactivates target swap")
if 'run(["umount", "-R", mountpoint], check=False)' not in source:
    raise SystemExit("installer no longer unmounts target filesystems")

# CI is not an ArchISO session. An install request must therefore fail before
# device validation or any destructive utility can run.
proc = subprocess.run(
    [sys.executable, str(helper), "install"],
    input=json.dumps({
        "device": "/dev/sda",
        "username": "tester",
        "password": "correct-horse",
        "confirm": "ERASE:/dev/sda",
    }),
    text=True,
    capture_output=True,
)
if proc.returncode == 0 or "live environment" not in proc.stdout:
    raise SystemExit("installer did not reject destructive operation outside live media")

print("Installer safety: discovery is read-only and install is gated by live/root/exact erase confirmation")

# The copied live system loses what only the live ISO needs. archiso.conf above
# all: mkinitcpio reads conf.d after mkinitcpio.conf, so leaving it built the
# installed boot image with archiso's hooks, which wait for the USB and stop.
sys.path.insert(0, str(root / "apps" / "settings"))
import golden_update  # noqa: E402
with tempfile.TemporaryDirectory() as td:
    target = Path(td)
    for rel in golden_update.LIVE_LEFTOVERS:
        p = target / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if rel.endswith(".wants"):
            p.mkdir()
            (p / "cloud-init-main.service").write_text("")
        else:
            p.write_text("live")
    (target / "etc/mkinitcpio.conf").write_text("HOOKS=(base systemd)\n")
    (target / "etc/systemd/system/multi-user.target.wants/NetworkManager.service").write_text("")
    assert golden_update.remove_live_leftovers(target) is True
    leftovers = [rel for rel in golden_update.LIVE_LEFTOVERS if (target / rel).exists()]
    assert not leftovers, leftovers
    assert (target / "etc/mkinitcpio.conf").exists()
    assert (target / "etc/systemd/system/multi-user.target.wants/NetworkManager.service").exists()
    assert golden_update.remove_live_leftovers(target) is False      # nothing left to rebuild
for must in ("etc/mkinitcpio.conf.d/archiso.conf", "etc/systemd/system/cloud-init.target.wants",
             "etc/systemd/journald.conf.d/volatile-storage.conf", "etc/systemd/system/etc-pacman.d-gnupg.mount"):
    assert must in golden_update.LIVE_LEFTOVERS, must
print("installer: live ISO leftovers removed from the installed system")


# The installed system logs in through SDDM, with no X server on the image: the
# greeter must run on Wayland (in Weston's kiosk shell), or the screen stays black.
install_sh = (root / "scripts" / "install.sh").read_text(encoding="utf-8")
packages = (root / "distro" / "archiso" / "packages.x86_64").read_text(encoding="utf-8").split()
assert "DisplayServer=wayland" in install_sh and "weston --shell=kiosk" in install_sh, "SDDM must use a Wayland greeter"
assert "weston" in packages and "sddm" in packages, "the Wayland greeter needs weston on the image"
print("installer: SDDM's login screen runs on Wayland")


# The image is an install of CitronOS's packages, and pacman keeps file modes:
# Software Update's helper (run directly by pkexec) and every other program
# must be executable in citronos-runtime as in the repository, or saving a
# token and installing updates fail with "command not found".
build_sh = (root / "distro" / "archiso" / "build.sh").read_text(encoding="utf-8")
assert os.access(root / "apps" / "settings" / "update-helper.py", os.X_OK), "update-helper.py must be executable"
assert "build_citronos" in build_sh and "scripts/install.sh\" --system" not in build_sh, \
    "the image installs the packages, not install.sh --system"
with tempfile.TemporaryDirectory() as t:
    staged = Path(t) / "runtime"
    subprocess.run(["bash", str(root / "scripts" / "stage.sh"), "runtime", str(staged)], check=True, capture_output=True)
    apps = staged / "usr/share/golden-gate/apps"
    assert os.access(apps / "settings" / "update-helper.py", os.X_OK), "the packaged update-helper.py isn't executable"
    lost = [str(p.relative_to(root)) for p in (root / "apps").rglob("*")
            if p.is_file() and os.access(p, os.X_OK) and "/lib/" not in str(p) and "__pycache__" not in str(p)
            and not os.access(apps / p.relative_to(root / "apps"), os.X_OK)]
    assert not lost, f"not executable in the package: {lost[:5]}"
# What airootfs itself has (the overlay's programs, gg-update-disk): mkarchiso
# copies it without modes, so build.sh's block gives the bit back. Run on the
# overlay, it must list each of the overlay's programs.
block = re.search(r"\{\n  echo 'file_permissions\+=\('\n  \(cd \"\$AIR\".*?\n\} >> \"\$PROFILE/profiledef.sh\"\n", build_sh, re.S)
assert block, "build.sh must give back the executable bit to airootfs's own programs"
with tempfile.TemporaryDirectory() as t:
    air, profile = Path(t) / "airootfs", Path(t) / "profile"
    profile.mkdir()
    shutil.copytree(root / "distro" / "archiso" / "overlay", air, symlinks=True)
    # What build.sh itself writes there before the block: the self-test,
    # gg-update-disk and the source bundle.
    for rel, mode in (("usr/lib/golden-gate/selftest.sh", 0o755), ("usr/local/bin/gg-update-disk", 0o755),
                      ("usr/share/golden-gate/source.tar.gz", 0o644)):
        (air / rel).parent.mkdir(parents=True, exist_ok=True)
        (air / rel).write_text("")
        (air / rel).chmod(mode)
    subprocess.run(["bash", "-euo", "pipefail", "-c", block.group(0)], check=True,
                   env={**os.environ, "AIR": str(air), "PROFILE": str(profile)})
    listed = dict(re.findall(r'\["(/[^"]+)"\]="0:0:(\d+)"', (profile / "profiledef.sh").read_text()))
    programs = [p for p in (air / "usr/local/bin").rglob("*") if p.is_file() and os.access(p, os.X_OK)]
    programs += [air / "usr/lib/golden-gate/selftest.sh"]
    assert air / "usr/local/bin/gg-session" in programs and air / "usr/local/bin/gg-update-disk" in programs, programs[:5]
    missing = [str(p.relative_to(air)) for p in programs if listed.get("/" + str(p.relative_to(air))) != "755"]
    assert not missing, f"not executable on the image: {missing}"
print("installer: CitronOS's programs stay executable on the image")

# The live session's self-test ships in the image but runs only for the boot
# test: its unit needs gg.selftest on the kernel command line, which only the
# boot test's std run adds.
unit = (root / "distro" / "archiso" / "selftest" / "citronos-selftest.service").read_text(encoding="utf-8")
assert "ConditionKernelCommandLine=gg.selftest" in unit, "the self-test must not run on a normal boot"
assert 'cmdline+=" gg.selftest"' in (root / "distro" / "archiso" / "boot-test.sh").read_text(encoding="utf-8")
assert "citronos-session.target.wants/citronos-selftest.service" in build_sh
assert os.access(root / "distro" / "archiso" / "selftest" / "selftest.sh", os.X_OK)
print("installer: the live session's self-test runs only for the boot test")
