#!/usr/bin/env python3
"""CitronOS as its packages install it (T-2.1): scripts/stage.sh, one part per
package (packaging/citronos/PKGBUILD), checked without Arch.

Each part is staged into a folder of its own, and:
- no file is in two packages, and nothing goes to /usr/local or a home folder;
- the shell is in /etc/xdg/quickshell/golden-gate, its ui/ the shared UI, and
  a new account gets no shell of its own, only a one-line hyprland.conf that
  sources the packaged settings (whose paths are all there);
- every gg-* command, D-Bus service and systemd unit runs something that is
  installed, and every desktop entry's apps path is;
- nothing staged is a build leftover (__pycache__) or points into the build.
packaging/check.sh builds the real packages and installs them on Arch (the
Packages workflow)."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PARTS = ("runtime", "shell", "hyprland-config", "theme")
TMP = Path(tempfile.mkdtemp())


def stage(part: str) -> Path:
    out = TMP / part
    subprocess.run([str(ROOT / "scripts/stage.sh"), part, str(out)], check=True, capture_output=True, timeout=600)
    return out


STAGED = {part: stage(part) for part in PARTS}


def files(root: Path) -> set[str]:
    return {"/" + str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() or p.is_symlink()}


def installed(path: str) -> bool:
    """Is it there once every package is installed?"""
    for root in STAGED.values():
        p = root / path.lstrip("/")
        if p.is_symlink():
            target = Path(p.readlink())
            return installed(str(target if target.is_absolute() else (Path(path).parent / target)))
        if p.exists():
            return True
    return False


class Layout(unittest.TestCase):
    def test_no_file_in_two_packages(self):
        seen: dict[str, str] = {}
        for part, root in STAGED.items():
            for f in files(root):
                self.assertNotIn(f, seen, f"{f} is in both {seen.get(f)} and {part}")
                seen[f] = part

    def test_only_system_places(self):
        for part, root in STAGED.items():
            for f in files(root):
                self.assertFalse(f.startswith(("/usr/local/", "/home/", "/root/")), f"{part}: {f}")
                self.assertTrue(f.startswith(("/usr/", "/etc/")), f"{part}: {f}")
                self.assertNotIn("__pycache__", f, f"{part}: {f}")

    def test_the_shell_is_the_systems(self):
        s = STAGED["shell"] / "etc/xdg/quickshell/golden-gate"
        self.assertTrue((s / "shell.qml").is_file())
        self.assertTrue((s / "lock-shell.qml").is_file())
        self.assertEqual(str((s / "ui").readlink()), "/usr/share/golden-gate/ui")
        self.assertTrue(installed("/usr/share/golden-gate/ui/theme/Release.qml"))
        for root in STAGED.values():
            self.assertFalse((root / "etc/skel/.config/quickshell").exists(), "a new account gets no shell of its own")

    def test_a_new_accounts_hyprland_conf_is_a_stub(self):
        stub = (STAGED["hyprland-config"] / "etc/skel/.config/hypr/hyprland.conf").read_text()
        lines = [l for l in stub.splitlines() if l.strip() and not l.startswith("#")]
        self.assertEqual(lines, ["source = /usr/share/golden-gate/hypr/hyprland.conf"])
        conf = (STAGED["hyprland-config"] / "usr/share/golden-gate/hypr/hyprland.conf").read_text()
        self.assertNotIn("__GG_", conf)
        # What it sources and runs from the system is there; per-account files
        # (~/.config/hypr/golden-gate) are made by gg-session.
        for path in re.findall(r"(/usr/share/golden-gate/[\w./-]+)", conf):
            self.assertTrue(installed(path), f"hyprland.conf uses {path}, which isn't installed")
        per_user = set(re.findall(r"^source = ~/.config/hypr/golden-gate/(\w+)\.conf", conf, re.M))
        session = (ROOT / "distro/archiso/overlay/usr/local/bin/gg-session").read_text()
        made = set(re.search(r"for f in ([\w ]+); do\n  \[ -e \"\$conf/\$f.conf\" \]", session).group(1).split())
        self.assertLessEqual(per_user - {"machine"}, made, "gg-session makes each per-account file hyprland.conf sources")


class References(unittest.TestCase):
    def test_commands(self):
        bins = sorted((STAGED["runtime"] / "usr/bin").iterdir())
        self.assertGreater(len(bins), 20)
        for b in bins:
            self.assertTrue(b.name.startswith("gg-"), b.name)
            m = re.search(r'^exec (?:\S+ )*?(/usr/\S+) "\$@"$', b.read_text(), re.M)
            if m:
                self.assertTrue(installed(m.group(1)), f"{b.name} runs {m.group(1)}, which isn't installed")

    def test_dbus_services_and_units(self):
        for f in (STAGED["runtime"] / "usr/share/dbus-1/services").glob("*.service"):
            exe = re.search(r"^Exec=(\S+)", f.read_text(), re.M).group(1)
            self.assertTrue(exe.startswith("/usr/bin/") and installed(exe), f"{f.name}: Exec={exe}")
        for f in (STAGED["runtime"] / "usr/lib/systemd/user").glob("citronos-*"):
            for exe in re.findall(r"^Exec\w*=(?:/usr/bin/env )?(\S+)", f.read_text(), re.M):
                if exe.startswith("gg-"):
                    self.assertTrue(installed("/usr/bin/" + exe), f"{f.name} runs {exe}")
        wants = STAGED["runtime"] / "usr/lib/systemd/user/default.target.wants"
        for link in wants.iterdir():
            self.assertTrue(installed(f"/usr/lib/systemd/user/default.target.wants/{link.name}"), link.name)

    def test_desktop_entries(self):
        for f in (STAGED["runtime"] / "usr/share/applications").glob("*.desktop"):
            text = f.read_text()
            self.assertNotIn("@APPS@", text, f.name)
            for path in re.findall(r"(/usr/share/golden-gate/apps/[\w./-]+)", text):
                self.assertTrue(installed(path), f"{f.name} uses {path}")

    def test_nothing_points_into_the_build(self):
        for part, root in STAGED.items():
            for p in root.rglob("*"):
                if p.is_symlink():
                    self.assertNotIn(str(TMP), str(p.readlink()), f"{part}: {p}")
                elif p.is_file() and p.suffix in (".conf", ".desktop", ".service", ".hook", "") and p.stat().st_size < 65536:
                    self.assertNotIn(str(TMP), p.read_text(errors="replace"), f"{part}: {p}")
                    self.assertNotIn(str(ROOT), p.read_text(errors="replace"), f"{part}: {p}")

    def test_sudoers_as_sudo_needs_it(self):
        d = STAGED["runtime"] / "etc/sudoers.d"
        self.assertEqual(d.stat().st_mode & 0o777, 0o750)
        self.assertEqual((d / "20-golden-wheel").stat().st_mode & 0o777, 0o440)


class Packages(unittest.TestCase):
    def test_one_package_per_part(self):
        pkgbuild = (ROOT / "packaging/citronos/PKGBUILD").read_text()
        for part in PARTS:
            self.assertIn(f"package_citronos-{part}()", pkgbuild)
            self.assertIn(f"install-{part} DESTDIR=\"$pkgdir\"", pkgbuild)
        makefile = (ROOT / "Makefile").read_text()
        self.assertIn("PARTS := " + " ".join(PARTS), makefile)


if __name__ == "__main__":
    unittest.main(verbosity=1)
