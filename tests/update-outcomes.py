#!/usr/bin/env python3
"""Software Update tells success from failure (apps/settings/update-helper.py
and golden_update.py, with every command mocked):

- the last event is "done" only when every part installed; a CitronOS
  download that failed, or system apps that didn't update, end in an error
  naming the part (and what did install), never "CitronOS is up to date";
- packages a new version requires must be available and install, or nothing
  is changed; optional ones left out are listed with why;
- a failure at any step after the files are replaced puts the previous
  version back (runtime, shell, system files, glass plugin; new files
  removed), journals where it stopped and says so;
- a glass plugin that couldn't be updated is a notice that says whether
  the one in place was made for the Hyprland installed now."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


helper = load("update_helper", "apps/settings/update-helper.py")
gu = helper.golden_update


class Outcomes(unittest.TestCase):
    def apply(self, pacman=0, flatpak=0, golden=lambda emit: "unchanged"):
        events = []
        rec = lambda event, **kw: events.append({"event": event, **kw})

        def stream(cmd, *a):
            return (flatpak, "error: Unable to load summary from remote flathub") if cmd[0] == "flatpak" else (pacman, "")
        with patch.object(helper, "emit", rec), patch.object(helper.os, "geteuid", return_value=0), \
                patch.object(helper.os.path, "exists", return_value=False), \
                patch.object(helper, "repair_keyring", lambda initial: None), \
                patch.object(helper, "system_upgrade", lambda: (pacman, "error: failed retrieving file 'core.db'" if pacman else "")), \
                patch.object(helper, "stream", stream), \
                patch.object(helper.shutil, "which", return_value="/usr/bin/flatpak"), \
                patch.object(gu, "apply", golden):
            code = helper.apply()
        return code, events

    def test_everything_installed(self):
        code, events = self.apply(golden=lambda emit: "updated")
        self.assertEqual(code, 0)
        self.assertEqual(events[-1]["event"], "done")
        self.assertTrue(events[-1]["restart"])

    def test_citronos_download_failure_is_not_success(self):
        def golden(emit):
            emit("error", message="CitronOS couldn't be downloaded: Download failed")
            return "failed"
        code, events = self.apply(golden=golden)
        self.assertEqual(code, 1)
        self.assertNotIn("done", [e["event"] for e in events])
        last = events[-1]
        self.assertEqual(last["event"], "error")
        self.assertIn("CitronOS: CitronOS couldn't be downloaded", last["message"])
        self.assertIn("System packages", last["message"], "and what did install")
        self.assertNotIn("up to date", last["message"])

    def test_system_apps_failure(self):
        code, events = self.apply(flatpak=1)
        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["event"], "error")
        self.assertIn("Apps for everyone: error: Unable to load summary", events[-1]["message"])
        parts = {p["name"]: p["ok"] for p in events[-1]["parts"]}
        self.assertEqual(parts, {"System packages": True, "Apps for everyone": False, "CitronOS": True})

    def test_system_packages_failure_with_citronos_updated(self):
        code, events = self.apply(pacman=1, golden=lambda emit: "updated")
        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["event"], "error")
        self.assertTrue(events[-1]["restart"], "CitronOS did update: log out to finish it")
        self.assertIn("Couldn't download the updates", events[-1]["message"])


class Staged(unittest.TestCase):
    """install_tree on a staging root, with install.sh and pacman mocked."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.root = base / "root"
        self.tree = base / "tree"
        for d in ("usr/share/golden-gate", "etc/skel/.config/quickshell/golden-gate", "usr/lib/golden-gate", "etc/gg"):
            (self.root / d).mkdir(parents=True)
        (self.root / "usr/share/golden-gate/old.qml").write_text("old runtime")
        (self.root / "etc/skel/.config/quickshell/golden-gate/shell.qml").write_text("old shell")
        (self.root / "etc/gg/existing.conf").write_text("old conf")
        (self.root / "usr/lib/golden-gate/hyprglass.so").write_bytes(b"old plugin")
        (self.tree / "scripts").mkdir(parents=True)
        # A stand-in install.sh: writes the new runtime, new-account shell, a
        # default config and a helper into the root it's given (the staging folder).
        (self.tree / "scripts/install.sh").write_text(
            '#!/bin/sh\nR="$2"\nmkdir -p "$R/usr/share/golden-gate/apps" "$R/usr/share/golden-gate/ui" '
            '"$R/etc/skel/.config/quickshell/golden-gate" "$R/etc/skel/.config/hypr" "$R/usr/lib/golden-gate"\n'
            'echo new > "$R/usr/share/golden-gate/apps/new.qml"\necho new > "$R/usr/share/golden-gate/ui/Theme.qml"\n'
            'echo "new shell" > "$R/etc/skel/.config/quickshell/golden-gate/shell.qml"\n'
            'echo "new hypr" > "$R/etc/skel/.config/hypr/hyprland.conf"\n'
            'echo "new rules" > "$R/usr/lib/golden-gate/account_rules.py"\n')
        (self.root / "usr/share/golden-gate/apps").mkdir(parents=True)
        (self.root / "usr/share/golden-gate/apps/old.qml").write_text("old app")
        (self.root / "etc/skel/.config/hypr").mkdir(parents=True)
        (self.root / "etc/skel/.config/hypr/hyprland.conf").write_text("old hypr")
        (self.root / "usr/lib/golden-gate/account_rules.py").write_text("old rules")
        # An account with the old shell and an unedited default config.
        self.home = self.root / "home/ada"
        (self.home / ".config/quickshell/golden-gate").mkdir(parents=True)
        (self.home / ".config/quickshell/golden-gate/shell.qml").write_text("old shell")
        (self.home / ".config/hypr").mkdir(parents=True)
        (self.home / ".config/hypr/hyprland.conf").write_text("old hypr")
        ov = self.tree / "distro/archiso/overlay"
        (ov / "etc/gg").mkdir(parents=True)
        (ov / "etc/gg/existing.conf").write_text("new conf")
        (ov / "etc/gg/added.conf").write_text("added")
        (self.tree / "distro/archiso/packages.x86_64").write_text("base\nnewdep\n")
        (self.tree / "distro/archiso/packages.extra").write_text("aur-thing\n")
        (self.tree / "distro/archiso/build.sh").write_text("# no services, no plugin pin\n")
        self.work = base / "work"
        self.work.mkdir()
        self.events = []
        self.patches = [patch.object(gu, "ROOT", self.root), patch.object(gu, "_accounts", lambda: iter([(type("E", (), {"pw_uid": os.getuid(), "pw_gid": os.getgid(), "pw_name": "ada"})(), self.home)])),
                        patch.object(gu, "update_hyprbars", lambda tree, emit: None),
                        patch.object(gu, "remove_live_leftovers", lambda root: False),
                        patch.object(gu, "ensure_keyring", lambda root: None)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def emit(self, event, **kw):
        self.events.append({"event": event, **kw})

    def pacman(self, available=("newdep",), installs=True):
        def run(cmd, **kw):
            if cmd[0] == "pacman" and "-T" in cmd:
                return subprocess.CompletedProcess(cmd, 127, "newdep\naur-thing\n", "")
            if cmd[0] == "pacman" and "-Si" in cmd:
                return subprocess.CompletedProcess(cmd, 0 if cmd[-1] in available else 1, "", "")
            if cmd[0] == "pacman" and "-S" in cmd:
                return subprocess.CompletedProcess(cmd, 0 if installs else 1, "", "" if installs else "error: failed to commit transaction (conflicting files)")
            if cmd[0] == "pacman" and "-Q" in cmd:
                return subprocess.CompletedProcess(cmd, 0, "hyprland 0.52.1-1\n", "")
            return subprocess.run(cmd, text=True, capture_output=True, **kw)
        return run

    def install(self, **kw):
        with patch.object(gu, "_run", self.pacman(**kw)), patch.object(gu.shutil, "which", return_value="/usr/bin/x"), \
                patch.object(gu, "path", lambda p: self.root / p.lstrip("/")):
            (self.root / "var/lib/pacman/local").mkdir(parents=True, exist_ok=True)
            return gu.install_tree(self.tree, {"commit": "abc123"}, self.emit, self.work)

    def journal(self):
        return json.loads((self.root / "var/lib/golden-gate/update-journal.json").read_text())

    def test_required_package_unavailable_changes_nothing(self):
        self.assertFalse(self.install(available=()))
        self.assertIn("packages the package repositories don't have", self.events[-1]["message"])
        self.assertIn("newdep", self.events[-1]["message"])
        self.assertEqual((self.root / "usr/share/golden-gate/apps/old.qml").read_text(), "old app")
        self.assertEqual((self.root / "etc/gg/existing.conf").read_text(), "old conf")
        self.assertEqual(self.journal()["state"], "failed")

    def test_required_package_that_wont_install(self):
        self.assertFalse(self.install(installs=False))
        self.assertIn("conflicting files", self.events[-1]["message"])

    def test_optional_left_out_with_why(self):
        self.assertTrue(self.install())
        notices = " ".join(e["message"] for e in self.events if e["event"] == "notice")
        self.assertIn("aur-thing (needs the AUR)", notices)
        self.assertEqual(self.journal()["state"], "installed")
        self.assertEqual((self.root / "etc/gg/existing.conf").read_text(), "new conf")
        self.assertEqual((self.home / ".config/quickshell/golden-gate/shell.qml").read_text().strip(), "new shell")
        self.assertEqual((self.root / "usr/lib/golden-gate/account_rules.py").read_text().strip(), "new rules")

    def test_a_later_failure_puts_everything_back(self):
        with patch.object(gu, "enable_services", side_effect=OSError("systemctl: Failed to enable unit")):
            self.assertFalse(self.install())
        msg = self.events[-1]["message"]
        self.assertIn("while turning on services", msg)
        self.assertIn("previous version was put back", msg)
        self.assertEqual((self.root / "usr/share/golden-gate/apps/old.qml").read_text(), "old app")
        self.assertFalse((self.root / "usr/share/golden-gate/apps/new.qml").exists())
        self.assertFalse((self.root / "usr/share/golden-gate/ui").exists(), "a tree the update added is removed")
        # Everything install.sh and the account refresh changed is back (R02).
        self.assertEqual((self.home / ".config/quickshell/golden-gate/shell.qml").read_text(), "old shell", "the account's shell")
        self.assertEqual((self.home / ".config/hypr/hyprland.conf").read_text(), "old hypr", "the account's config")
        self.assertEqual((self.root / "etc/skel/.config/hypr/hyprland.conf").read_text(), "old hypr", "the default config")
        self.assertEqual((self.root / "usr/lib/golden-gate/account_rules.py").read_text(), "old rules", "the system helper")
        self.assertEqual((self.root / "etc/skel/.config/quickshell/golden-gate/shell.qml").read_text(), "old shell")
        self.assertIn("services it turns on stay on", msg, "and it says what wasn't undone")
        self.assertEqual((self.root / "etc/gg/existing.conf").read_text(), "old conf")
        self.assertFalse((self.root / "etc/gg/added.conf").exists(), "a file the update added is removed")
        self.assertEqual((self.root / "usr/lib/golden-gate/hyprglass.so").read_bytes(), b"old plugin")
        j = self.journal()
        self.assertEqual((j["state"], j["step"]), ("failed", "turning on services"))
        self.assertTrue((self.root / "var/lib/golden-gate/rollback/manifest.json").exists(), "the copy is kept")

    def test_glass_plugin_failure_is_said(self):
        (self.root / "usr/lib/golden-gate/hyprglass.so.hyprland").write_text("0.49.0\n")
        with patch.object(gu, "update_hyprglass", side_effect=OSError("network unreachable")):
            self.assertTrue(self.install())
        notices = " ".join(e["message"] for e in self.events if e["event"] == "notice")
        self.assertIn("Liquid Glass plugin couldn't be updated", notices)
        self.assertIn("Hyprland 0.49.0, not 0.52.1", notices)


class GlassPlugin(unittest.TestCase):
    """The plugin goes only with the Hyprland it was built for (R11)."""
    def setUp(self):
        import hashlib
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "root"
        (self.root / "usr/lib/golden-gate").mkdir(parents=True)
        self.tree = Path(self.tmp.name) / "tree"
        (self.tree / "distro/archiso").mkdir(parents=True)
        self.bytes = b"plugin built for 0.56.2"
        (self.tree / "distro/archiso/build.sh").write_text(
            f'HYPRGLASS_VERSION="v0.8.1"\nHYPRGLASS_SHA256="{hashlib.sha256(self.bytes).hexdigest()}"\nHYPRGLASS_HYPRLAND="0.56.2"\n')
        self.events = []

    def tearDown(self):
        self.tmp.cleanup()

    def update(self, installed, have=True, download=None):
        plugin = self.root / "usr/lib/golden-gate/hyprglass.so"
        if have:
            plugin.write_bytes(self.bytes)
        fetched = []

        class R:
            def __init__(s, data): s.data = data
            def __enter__(s): return s
            def __exit__(s, *a): pass
            def read(s): return s.data

        with patch.object(gu, "ROOT", self.root), patch.object(gu, "path", lambda p: self.root / p.lstrip("/")), \
                patch.object(gu, "hyprland_release", return_value=installed), \
                patch.object(gu.urllib.request, "urlopen", lambda *a, **k: fetched.append(a) or R(download or self.bytes)):
            gu.update_hyprglass(self.tree, lambda e, **k: self.events.append({"event": e, **k}))
        return plugin, fetched

    def test_checksum_hit_with_another_hyprland(self):
        plugin, fetched = self.update("0.57.0")
        self.assertTrue(plugin.with_name("hyprglass.so.incompatible").exists(), "marked: gg-hyprglass-sync won't load it")
        self.assertIn("Hyprland 0.57.0 is installed", " ".join(e["message"] for e in self.events))
        self.assertEqual(fetched, [])

    def test_matching_hyprland(self):
        plugin, _ = self.update("0.56.2")
        self.assertEqual(plugin.with_name("hyprglass.so.hyprland").read_text().strip(), "0.56.2")
        self.assertFalse(plugin.with_name("hyprglass.so.incompatible").exists())
        self.assertEqual(self.events, [])

    def test_download_is_stamped_with_its_build_target(self):
        plugin, fetched = self.update("0.56.2", have=False)
        self.assertEqual(len(fetched), 1)
        self.assertEqual(plugin.read_bytes(), self.bytes)
        self.assertEqual(plugin.with_name("hyprglass.so.hyprland").read_text().strip(), "0.56.2",
                         "the pin's Hyprland, not just whatever is installed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
