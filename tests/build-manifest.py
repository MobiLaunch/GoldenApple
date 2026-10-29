#!/usr/bin/env python3
"""The ISO is built from pinned inputs and says what it's made of (T-2.2):

- every AUR package the image builds is pinned to a commit of its AUR
  repository (distro/archiso/aur-pins), and build.sh builds that commit and
  refuses one that isn't pinned;
- build-manifest.json (distro/archiso/manifest.py) holds the inputs build.sh
  pins and every package with its version, and nothing that depends on when
  or where it was built: the same inputs give the same file, byte for byte;
- the Build ISO workflow keeps the manifest, and builds when the packages'
  sources change (the image is an install of them)."""
from __future__ import annotations

import json
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HERE = ROOT / "distro/archiso"
BUILD = (HERE / "build.sh").read_text()
# Built by build.sh itself (BlueFerry, from its tag), or in Arch's repositories
# as of distro/archive-date (Quickshell, in [extra]): not from the AUR.
NOT_FROM_THE_AUR = {"blueferry-backend", "quickshell"}


def extra() -> list[str]:
    return [l.strip() for l in (HERE / "packages.extra").read_text().splitlines() if l.strip() and not l.startswith("#")]


def pins() -> dict[str, list[str]]:
    out = {}
    for line in (HERE / "aur-pins").read_text().splitlines():
        words = line.split("#", 1)[0].split()
        if words:
            out[words[0]] = words[1:]
    return out


def run_manifest(pkglist: str, commit="d032cf81699b1873e6f1760a1a19a43e51261209"):
    with tempfile.TemporaryDirectory() as tmp:
        listing = Path(tmp) / "packages.txt"
        listing.write_text(pkglist)
        return subprocess.run([sys.executable, str(HERE / "manifest.py"), "--repo", str(ROOT), "--commit", commit,
                               "--packages", str(listing)], capture_output=True, text=True)


PKGLIST = "base 3-2\ncitronos 4.0.r20261029043505.gb701e45-1\nhyprland 0.56.2-4\npiper-tts 1.8.0-1\nuxplay 1.73.7-1\n"


class Pins(unittest.TestCase):
    def test_every_aur_package_is_pinned_to_a_commit(self):
        p = pins()
        self.assertEqual(set(p), set(extra()) - NOT_FROM_THE_AUR,
                         "aur-pins has exactly the packages.extra entries built from the AUR")
        for name, (commit, *version) in p.items():
            self.assertRegex(commit, r"^[0-9a-f]{40}$", name)
            self.assertTrue(version and re.fullmatch(r"[^-\s]+-\d+", version[0]), f"{name}: the version it builds")

    def test_build_sh_builds_the_pinned_commit(self):
        block = BUILD[BUILD.index("build_aur() {"):BUILD.index("\n}\n", BUILD.index("build_aur() {"))]
        self.assertIn('"$HERE/aur-pins"', block)
        self.assertIn('checkout -q "$pin"', block)
        self.assertIn("isn't pinned", block, "an AUR package that isn't pinned stops the build")
        self.assertLess(block.index('checkout -q "$pin"'), block.index("makepkg --syncdeps"), "checked out before it's built")


class Manifest(unittest.TestCase):
    def test_what_it_holds(self):
        proc = run_manifest(PKGLIST)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        m = json.loads(proc.stdout)
        self.assertEqual(m["archive"], (ROOT / "distro/archive-date").read_text().strip())
        self.assertEqual(m["citronos"], {"commit": "d032cf81699b1873e6f1760a1a19a43e51261209",
                                         "version": "4.0.r20261029043505.gb701e45-1"})
        self.assertEqual({k: v["commit"] for k, v in m["aur"].items()}, {k: v[0] for k, v in pins().items()})
        self.assertEqual(m["blueferry"], re.search(r'^BLUEFERRY_TAG=(\S+)', BUILD, re.M).group(1))
        self.assertEqual(m["hyprglass"]["sha256"], re.search(r'^HYPRGLASS_SHA256="(\w+)"', BUILD, re.M).group(1))
        self.assertEqual(m["hyprglass"]["hyprland"], "0.56.2")
        self.assertEqual(m["packages"]["hyprland"], "0.56.2-4")

    def test_the_same_inputs_give_the_same_file(self):
        lines = PKGLIST.splitlines()
        first = run_manifest(PKGLIST).stdout
        random.Random(4).shuffle(lines)
        self.assertEqual(run_manifest("\n".join(lines) + "\n").stdout, first, "pacman's order doesn't matter")
        self.assertEqual(run_manifest(PKGLIST).stdout, first)
        self.assertNotRegex(first, r"20\d\d-\d\d-\d\dT", "no time of building in it")

    def test_an_empty_package_list_is_an_error(self):
        proc = run_manifest("")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("empty", proc.stderr)


class Workflow(unittest.TestCase):
    def test_the_manifest_is_kept_and_written(self):
        iso = (ROOT / ".github/workflows/iso.yml").read_text()
        self.assertIn("path: out/build-manifest.json", iso)
        self.assertRegex(iso, r"pacman -Syuu [^\n]*\bpython\b", "the build has Python for manifest.py")
        self.assertIn('manifest.py" --repo "$REPO"', BUILD)
        self.assertIn('> "$OUT/build-manifest.json"', BUILD)

    def test_packaging_changes_build_the_iso(self):
        iso = (ROOT / ".github/workflows/iso.yml").read_text()
        paths = iso[iso.index("paths:"):iso.index("concurrency:")]
        for p in ("packaging/**", "scripts/stage.sh", "Makefile"):
            self.assertIn(f"- {p}", paths)


if __name__ == "__main__":
    unittest.main(verbosity=2)
