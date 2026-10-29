#!/usr/bin/env python3
"""Software Update installs CitronOS as its packages (T-2.1,
apps/settings/golden_update.py), on a staging root, with makepkg and pacman
stood in for: makepkg makes the five packages, and pacman keeps a real
/var/lib/pacman/local in the root, refuses files that are in the way as
pacman does, and upgrades in place.

- From a system scripts/install.sh made: its files in the packages' way go
  aside, the packages install, and its leftovers (/usr/local/bin's gg-*,
  /etc/skel's shell, copies of the packaged hooks) are removed; each account's
  shell copy becomes a link to the system's (gg-session removes it at the
  next login), an unedited hyprland.conf becomes the one-line stub, and copies
  of what is now the system's go unless edited or still used.
- An upgrade of the packages removes what the new ones no longer have.
- A failure after pacman puts back every file and pacman's records of them.
- A build that fails, or a version from before the packages over them,
  changes nothing.
- The packages are built by makepkg as an account of its own, in a copy
  without .git that only it can change, at a
  version pacman orders by date."""
from __future__ import annotations

import gzip
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("golden_update", ROOT / "apps/settings/golden_update.py")
gu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gu)

STUB = "source = /usr/share/golden-gate/hypr/hyprland.conf\n"
OLD_HYPR = "source = ~/.config/hypr/golden-gate/motion.conf\nexec-once = sh ~/.config/hypr/golden-gate/report-config-errors.sh\n"


def contents(version: str) -> dict[str, dict[str, str]]:
    """What each package built at `version` holds."""
    return {
        "citronos-runtime": {"usr/bin/gg-settings": f"#!/bin/sh\n# {version}\n",
                             "etc/sudoers.d/20-golden-wheel": "%wheel ALL=(ALL:ALL) ALL\n",
                             "usr/share/golden-gate/ui/Theme.qml": f"Theme {version}",
                             "usr/share/golden-gate/os-release": f'NAME="CitronOS"\nVERSION="{version}"\n',
                             **({"usr/share/golden-gate/ui/Old.qml": "gone next time"} if version.startswith("1") else {})},
        "citronos-shell": {"etc/xdg/quickshell/golden-gate/shell.qml": f"shell {version}"},
        "citronos-hyprland-config": {"etc/skel/.config/hypr/hyprland.conf": STUB,
                                     "usr/share/golden-gate/hypr/hyprland.conf": f"hypr {version}"},
        "citronos-theme": {"etc/skel/.config/gtk-4.0/gtk.css": f"css {version}"},
        "citronos": {},
    }


def dirs_of(files) -> set[str]:
    out = set()
    for f in files:
        for parent in Path(f).parents:
            if str(parent) != ".":
                out.add(str(parent) + "/")
    return out


class FakeSystem:
    """makepkg and pacman, over a staging root."""

    def __init__(self, root: Path, version="2.0", build_ok=True, pacman_ok=True):
        self.root, self.version, self.build_ok, self.pacman_ok = root, version, build_ok, pacman_ok
        self.calls: list[tuple[list[str], dict]] = []
        self.local = root / "var/lib/pacman/local"
        self.local.mkdir(parents=True, exist_ok=True)
        # The filesystem package's folders, where removing leftovers stops.
        self.record("filesystem", "2024-1", {}, extra_dirs=["etc/", "etc/pacman.d/", "etc/pacman.d/hooks/", "usr/",
                                                           "usr/local/", "usr/local/bin/", "usr/lib/", "home/"])

    def record(self, name, ver, files: dict, extra_dirs=()):
        d = self.local / f"{name}-{ver}"
        d.mkdir(parents=True)
        (d / "files.json").write_text(json.dumps(sorted(files) + sorted(dirs_of(files) | set(extra_dirs))))
        # pacman's record of each file and folder, as makepkg wrote it.
        mode = lambda f: "750" if f == "etc/sudoers.d" else "755"
        lines = ["#mtree", "/set type=file uid=0 gid=0 mode=644"]
        lines += [f"./{f.rstrip('/').replace(' ', chr(92) + '040')} time=1.0 mode={mode(f.rstrip('/'))} type=dir"
                  for f in sorted(dirs_of(files))]
        lines += [f"./{f.replace(' ', chr(92) + '040')} time=1.0 size=1" for f in sorted(files)]
        with gzip.open(d / "mtree", "wt") as m:
            m.write("\n".join(lines) + "\n")

    def installed(self) -> dict[str, Path]:
        out = {}
        for d in self.local.iterdir():
            m = re.match(r"^(.+)-([^-]+)-([^-]+)$", d.name)
            out[m.group(1) if m else d.name] = d
        return out

    def owned(self) -> set[str]:
        return {f for d in self.installed().values() for f in json.loads((d / "files.json").read_text())}

    def install(self, name: str, ver: str, files: dict):
        """As pacman -U does, for one package."""
        for f, text in files.items():
            p = self.root / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        old = self.installed().get(name)
        if old:
            for f in json.loads((old / "files.json").read_text()):
                if not f.endswith("/") and f not in files:
                    (self.root / f).unlink(missing_ok=True)
            shutil.rmtree(old)
        self.record(name, ver, files)

    def run(self, cmd, **kw):
        self.calls.append((cmd, kw))
        ok = lambda out="": subprocess.CompletedProcess(cmd, 0, out, "")
        if cmd[0] == "makepkg":
            here = Path(kw["cwd"])
            top = here.parents[1]
            self.build_seen = {"git": (top / ".git").exists(), "mode": top.stat().st_mode & 0o777,
                               "PKGBUILD": (here / "PKGBUILD").is_file()}
            if not self.build_ok:
                return subprocess.CompletedProcess(cmd, 4, "==> Starting build()...\n", "==> ERROR: A failure occurred in build().\n")
            ver = kw["env"]["CITRONOS_PKGVER"]
            for name, files in contents(self.version).items():
                (here / f"{name}-{ver}-1-any.pkg.tar.zst").write_text(json.dumps({"name": name, "files": files}))
            return ok()
        if cmd[0] != "pacman":
            return subprocess.run(cmd, text=True, capture_output=True, **kw)
        args = [a for a in cmd[1:] if not a.startswith("--sysroot")]
        args = [a for a in args if a != str(self.root)]
        if args[:1] == ["-T"]:
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if args[:1] == ["-Qq"]:
            return ok("\n".join(sorted(self.installed())) + "\n")
        if args[:1] == ["-Qlq"]:
            names = args[1:]
            have = self.installed()
            files = self.owned() if not names else \
                {f for n in names for f in json.loads((have[n] / "files.json").read_text())}
            return ok("".join("/" + f + "\n" for f in sorted(files)))
        if args[:1] == ["-Qlpq"]:
            pkg = json.loads((self.root / args[1].lstrip("/")).read_text())
            files = set(pkg["files"]) | dirs_of(pkg["files"])
            return ok("".join("/" + f + "\n" for f in sorted(files)))
        if args[:1] == ["-Q"]:
            return subprocess.CompletedProcess(cmd, 1, "", "error: package 'hyprland' was not found\n")
        if args[:1] == ["-U"]:
            if not self.pacman_ok:
                return subprocess.CompletedProcess(cmd, 1, "", "error: failed to commit transaction (invalid or corrupted package)\n")
            pkgs = [json.loads((self.root / a.lstrip("/")).read_text()) | {"file": a} for a in args if a.startswith("/")]
            owned_by = {}
            for name, d in self.installed().items():
                for f in json.loads((d / "files.json").read_text()):
                    owned_by[f] = name
            for pkg in pkgs:
                for f in pkg["files"]:
                    if os.path.lexists(self.root / f) and owned_by.get(f) != pkg["name"]:
                        return subprocess.CompletedProcess(cmd, 1, "", f"{pkg['name']}: /{f} exists in filesystem\n"
                                                           "error: failed to commit transaction (conflicting files)\n")
            for pkg in pkgs:
                ver = "-".join(Path(pkg["file"]).name.split("-")[-3:-1])
                self.install(pkg["name"], ver, pkg["files"])
            return ok()
        return ok()


class Packaged(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.root, self.tree, self.work = base / "root", base / "tree", base / "work"
        self.work.mkdir()
        # The new version: a tree with the PKGBUILD (and a .git the build leaves out).
        for f, text in {"packaging/citronos/PKGBUILD": "pkgname=(citronos)\n", ".git/HEAD": "ref: x\n",
                        "apps/lib/theme/Release.qml": 'QtObject { property string version: "4.1" }\n',
                        "scripts/install.sh": "#!/bin/sh\nexit 1\n",
                        "distro/archiso/build.sh": "# no services, no plugin pin\n",
                        "distro/archiso/packages.x86_64": "base\n"}.items():
            (self.tree / f).parent.mkdir(parents=True, exist_ok=True)
            (self.tree / f).write_text(text)
        (self.root / "usr/lib").mkdir(parents=True)
        (self.root / "usr/lib/os-release").write_text('NAME="Arch Linux"\n')
        self.events = []
        self.accounts = []

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def account(self, name):
        home = self.root / "home" / name
        (home / ".config").mkdir(parents=True)
        self.accounts.append((type("E", (), {"pw_uid": os.getuid(), "pw_gid": os.getgid(), "pw_name": name})(), home))
        return home

    def install_sh_system(self):
        """What scripts/install.sh --system left: no packages, its own files."""
        self.write("usr/share/golden-gate/ui/Theme.qml", "Theme install.sh")
        self.write("usr/local/bin/gg-settings", "#!/bin/sh\nexec python3 /usr/share/golden-gate/apps/settings/x\n")
        self.write("usr/share/golden-gate/runtime/settingsd.py", "old helper")
        self.write("etc/skel/.config/quickshell/golden-gate/shell.qml", "shell install.sh")
        self.write("etc/skel/.config/hypr/hyprland.conf", OLD_HYPR)
        self.write("etc/skel/.config/hypr/golden-gate/motion.conf", "motion install.sh")
        self.write("etc/skel/.config/hypr/golden-gate/report-config-errors.sh", "report install.sh")
        self.write("etc/skel/.config/fontconfig/conf.d/60-golden-gate.conf", "fonts install.sh")
        self.write("etc/skel/.config/systemd/user/citronpods-daemon.service", "unit install.sh")
        self.write("etc/pacman.d/hooks/citronos-pacman.hook", "a copy of the packaged hook")
        self.write("etc/sudoers.d/20-golden-wheel", "%wheel ALL=(ALL:ALL) ALL\n")
        (self.root / "etc/sudoers.d").chmod(0o755)          # install.sh's mode; the package has 750
        # Ada never changed anything; Bob edited hyprland.conf and his fonts.
        for name in ("ada", "bob"):
            home = self.account(name)
            conf = home / ".config"
            shutil.copytree(self.root / "etc/skel/.config", conf, dirs_exist_ok=True)
        (self.root / "home/bob/.config/hypr/hyprland.conf").write_text(OLD_HYPR + "bind = SUPER, B, exec, firefox\n")
        (self.root / "home/bob/.config/fontconfig/conf.d/60-golden-gate.conf").write_text("fonts, Bob's way")

    def install(self, system: FakeSystem, tree=None, **patches):
        extra = [patch.object(gu, k, v) for k, v in patches.items()]
        with patch.object(gu, "ROOT", self.root), patch.object(gu, "path", lambda p: self.root / p.lstrip("/")), \
                patch.object(gu, "_run", system.run), patch.object(gu.shutil, "which", return_value="/usr/bin/x"), \
                patch.object(gu, "_accounts", lambda: iter(self.accounts)), \
                patch.object(gu, "update_hyprbars", lambda tree, emit: None), \
                patch.object(gu, "update_hyprglass", lambda tree, emit=None: None), \
                patch.object(gu, "remove_live_leftovers", lambda root: False), \
                patch.object(gu, "ensure_keyring", lambda root: None), \
                patch.object(gu, "_builder", lambda: gu.pwd.getpwnam("nobody")):
            for p in extra:
                p.start()
            try:
                return gu.install_tree(tree or self.tree, {"commit": "abc1234def", "date": "2026-10-29T03:13:17Z"},
                                       lambda e, **k: self.events.append({"event": e, **k}), self.work)
            finally:
                for p in extra:
                    p.stop()

    def read(self, rel):
        return (self.root / rel).read_text()

    def last(self):
        return self.events[-1]["message"] if self.events else ""

    # ------------------------------------------------------------ from install.sh
    def test_from_an_install_sh_system(self):
        self.install_sh_system()
        system = FakeSystem(self.root)
        self.assertTrue(self.install(system), self.last())
        self.assertEqual(sorted(n for n in system.installed() if n.startswith("citronos")), sorted(gu.PACKAGES))
        self.assertEqual(self.read("usr/share/golden-gate/ui/Theme.qml"), "Theme 2.0", "install.sh's file went aside for the package's")
        self.assertIn('VERSION="2.0"', self.read("usr/lib/os-release"), "named for the new version")
        self.assertEqual((self.root / "etc/sudoers.d").stat().st_mode & 0o777, 0o750,
                         "a folder install.sh made has the package's mode (pacman leaves it as it was)")
        for gone in ("usr/local/bin/gg-settings", "usr/share/golden-gate/runtime", "etc/skel/.config/quickshell",
                     "etc/skel/.config/hypr/golden-gate", "etc/skel/.config/fontconfig", "etc/skel/.config/systemd",
                     "etc/pacman.d/hooks/citronos-pacman.hook"):
            self.assertFalse(os.path.lexists(self.root / gone), f"install.sh's {gone} is left")
        self.assertTrue((self.root / "usr/local/bin").is_dir(), "a folder a package has stays, empty or not")
        self.assertTrue((self.root / "etc/pacman.d/hooks").is_dir())

        ada = self.root / "home/ada/.config"
        self.assertTrue((ada / "quickshell/golden-gate").is_symlink())
        self.assertEqual(os.readlink(ada / "quickshell/golden-gate"), "/etc/xdg/quickshell/golden-gate")
        self.assertEqual((ada / "hypr/hyprland.conf").read_text(), STUB, "an unedited hyprland.conf is the stub")
        for gone in ("hypr/golden-gate/motion.conf", "hypr/golden-gate/report-config-errors.sh",
                     "fontconfig/conf.d/60-golden-gate.conf", "systemd/user/citronpods-daemon.service"):
            self.assertFalse((ada / gone).exists(), f"Ada's unedited {gone} (the system's now) is left")
        bob = self.root / "home/bob/.config"
        self.assertIn("firefox", (bob / "hypr/hyprland.conf").read_text(), "an edited hyprland.conf is Bob's")
        self.assertEqual((bob / "hypr/hyprland.conf.golden-gate-new").read_text(), STUB)
        self.assertTrue((bob / "hypr/golden-gate/motion.conf").exists(), "his hyprland.conf still uses it")
        self.assertTrue((bob / "hypr/golden-gate/report-config-errors.sh").exists())
        self.assertEqual((bob / "fontconfig/conf.d/60-golden-gate.conf").read_text(), "fonts, Bob's way")
        self.assertFalse((bob / "systemd/user/citronpods-daemon.service").exists())
        self.assertIn("hypr/hyprland.conf", " ".join(e["message"] for e in self.events if e["event"] == "notice"))
        self.assertEqual(json.loads(self.read("var/lib/golden-gate/update-journal.json"))["state"], "installed")

    def test_built_by_its_own_account_from_a_copy(self):
        system = FakeSystem(self.root)
        self.assertTrue(self.install(system), self.last())
        cmd, kw = next(c for c in system.calls if c[0][0] == "makepkg")
        self.assertEqual(kw["env"]["CITRONOS_PKGVER"], "4.1.r20261029031317.gabc1234")
        here = Path(kw["cwd"])
        self.assertEqual(here, self.work / "build/packaging/citronos")
        self.assertTrue(system.build_seen["PKGBUILD"])
        self.assertFalse(system.build_seen["git"], "the build's copy leaves out .git")
        if os.geteuid() == 0:
            self.assertEqual(kw["user"], gu.pwd.getpwnam("nobody").pw_uid, "makepkg won't build as root")
            self.assertEqual(system.build_seen["mode"], 0o700, "only the builder changes its copy")
        u = next(c[0] for c in system.calls if c[0][:2] == ["pacman", "--sysroot"] and "-U" in c[0])
        self.assertTrue(all(p.startswith("/var/cache/golden-gate/packages/") for p in u if p.endswith(".zst")),
                        "pacman --sysroot reads them inside the root")
        self.assertEqual(len([p for p in u if p.endswith(".zst")]), 5)

    # ------------------------------------------------------------ upgrades
    def test_an_upgrade_removes_what_the_new_packages_dont_have(self):
        system = FakeSystem(self.root, version="1.0")
        self.assertTrue(self.install(system), self.last())
        self.assertTrue((self.root / "usr/share/golden-gate/ui/Old.qml").exists())
        system.version = "2.0"
        self.assertTrue(self.install(system), self.last())
        self.assertFalse((self.root / "usr/share/golden-gate/ui/Old.qml").exists())
        self.assertEqual(self.read("etc/xdg/quickshell/golden-gate/shell.qml"), "shell 2.0")
        self.assertEqual(len([d for d in system.local.iterdir() if d.name.startswith("citronos-runtime-")]), 1)

    def test_a_failure_after_pacman_puts_back_files_and_records(self):
        system = FakeSystem(self.root, version="1.0")
        self.assertTrue(self.install(system), self.last())
        records = sorted(d.name for d in system.local.iterdir())
        system.version = "2.0"
        self.events.clear()
        self.assertFalse(self.install(system, enable_services=lambda tree: (_ for _ in ()).throw(OSError("systemctl: Failed"))))
        self.assertIn("previous version was put back", self.last())
        self.assertEqual(sorted(d.name for d in system.local.iterdir()), records, "pacman's records are the old ones")
        self.assertEqual(self.read("etc/xdg/quickshell/golden-gate/shell.qml"), "shell 1.0")
        self.assertEqual(self.read("usr/share/golden-gate/ui/Old.qml"), "gone next time")
        self.assertEqual(json.loads(self.read("var/lib/golden-gate/update-journal.json"))["step"], "turning on services")

    def test_a_failed_migration_puts_install_sh_back(self):
        self.install_sh_system()
        system = FakeSystem(self.root)
        self.assertFalse(self.install(system, enable_services=lambda tree: (_ for _ in ()).throw(OSError("systemctl: Failed"))))
        self.assertIn("previous version was put back", self.last())
        self.assertEqual([n for n in system.installed() if n.startswith("citronos")], [], "no packages recorded")
        self.assertFalse((self.root / "etc/xdg/quickshell/golden-gate").exists(), "what the packages added is gone")
        self.assertEqual(self.read("usr/share/golden-gate/ui/Theme.qml"), "Theme install.sh")
        self.assertTrue((self.root / "usr/local/bin/gg-settings").exists())
        self.assertEqual(self.read("etc/skel/.config/quickshell/golden-gate/shell.qml"), "shell install.sh")
        self.assertEqual(self.read("etc/pacman.d/hooks/citronos-pacman.hook"), "a copy of the packaged hook")
        ada = self.root / "home/ada/.config"
        self.assertFalse((ada / "quickshell/golden-gate").is_symlink())
        self.assertEqual((ada / "quickshell/golden-gate/shell.qml").read_text(), "shell install.sh")
        self.assertEqual((ada / "hypr/hyprland.conf").read_text(), OLD_HYPR)
        self.assertEqual((ada / "hypr/golden-gate/motion.conf").read_text(), "motion install.sh")
        self.assertEqual(self.read("usr/lib/os-release"), 'NAME="Arch Linux"\n')
        self.assertEqual((self.root / "etc/sudoers.d").stat().st_mode & 0o777, 0o755, "its mode is back too")

    def test_pacman_refusing_changes_nothing_it_had(self):
        self.install_sh_system()
        system = FakeSystem(self.root, pacman_ok=False)
        self.assertFalse(self.install(system))
        self.assertIn("packages didn't install", self.last())
        self.assertIn("invalid or corrupted package", self.last())
        self.assertEqual(self.read("usr/share/golden-gate/ui/Theme.qml"), "Theme install.sh", "the file set aside is back")
        self.assertTrue((self.root / "usr/local/bin/gg-settings").exists())

    # ------------------------------------------------------------ refusals
    def test_a_build_that_fails_changes_nothing(self):
        self.install_sh_system()
        system = FakeSystem(self.root, build_ok=False)
        self.assertFalse(self.install(system))
        self.assertIn("couldn't be built (==> ERROR: A failure occurred in build().)", self.last())
        self.assertIn("Nothing was changed", self.last())
        self.assertFalse(any(c[0][0] == "pacman" and "-U" in c[0] for c in system.calls))
        self.assertEqual(self.read("usr/share/golden-gate/ui/Theme.qml"), "Theme install.sh")
        self.assertTrue((self.root / "home/ada/.config/quickshell/golden-gate").is_dir())

    def test_a_version_from_before_the_packages_isnt_installed_over_them(self):
        system = FakeSystem(self.root)
        self.assertTrue(self.install(system), self.last())
        (self.tree / "packaging/citronos/PKGBUILD").unlink()
        self.assertFalse(self.install(system))
        self.assertIn("older than its packages", self.last())
        self.assertEqual(self.read("etc/xdg/quickshell/golden-gate/shell.qml"), "shell 2.0")

    def test_versions_pacman_orders_by_date(self):
        tree = self.tree
        v = lambda **k: gu.package_version(tree, k)
        self.assertEqual(v(commit="d032cf81699b", date="2026-10-29T03:13:17Z"), "4.1.r20261029031317.gd032cf8")
        self.assertEqual(v(commit="abc1234", date="2026-10-29T05:13:17+02:00"), "4.1.r20261029031317.gabc1234", "in UTC")
        self.assertRegex(v(commit="", date=""), r"^4\.1\.r\d{14}\.gunknown$")
        self.assertRegex(v(commit="xyz; rm -rf /", date="soon"), r"^4\.1\.r\d{14}\.gunknown$")


class SessionLink(unittest.TestCase):
    """gg-session removes the link Software Update left in place of an
    account's shell copy, and nothing else."""
    def session_prelude(self, home: Path):
        script = (ROOT / "distro/archiso/overlay/usr/local/bin/gg-session").read_text()
        block = script[script.index("shell_link="):script.index("fi\n", script.index("shell_link=")) + 3]
        subprocess.run(["sh", "-c", block], env={"HOME": str(home), "PATH": "/usr/bin:/bin"}, check=True)

    def test_the_link_goes(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".config/quickshell").mkdir(parents=True)
            (home / ".config/quickshell/golden-gate").symlink_to("/etc/xdg/quickshell/golden-gate")
            self.session_prelude(home)
            self.assertFalse(os.path.lexists(home / ".config/quickshell"))

    def test_an_accounts_own_shell_stays(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".config/quickshell/golden-gate").mkdir(parents=True)
            (home / ".config/quickshell/other").mkdir(parents=True)
            self.session_prelude(home)
            self.assertTrue((home / ".config/quickshell/golden-gate").is_dir(), "a developer's own copy")
            (home / ".config/quickshell/golden-gate").rmdir()
            (home / ".config/quickshell/golden-gate").symlink_to("/etc/xdg/quickshell/golden-gate")
            self.session_prelude(home)
            self.assertTrue((home / ".config/quickshell/other").is_dir(), "another Quickshell config stays")


if __name__ == "__main__":
    unittest.main(verbosity=2)
