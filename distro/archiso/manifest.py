#!/usr/bin/env python3
"""What a CitronOS image is made of (T-2.2), as build-manifest.json: the
inputs build.sh pins (the Arch Linux Archive date, the AUR commits, BlueFerry's
tag, the HyprGlass plugin) and every package in the image with its version.
Nothing in it depends on when or where the image was built, so two builds of
one CitronOS commit give the same manifest, and two manifests' difference is
what changed in the image.

    manifest.py --repo REPO --commit SHA --packages PKGLIST > build-manifest.json

PKGLIST is `pacman -Q` of the image ("name version" lines)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys


def pins(path: Path) -> dict[str, dict[str, str]]:
    out = {}
    for line in path.read_text().splitlines():
        words = line.split("#", 1)[0].split()
        if words:
            out[words[0]] = {"commit": words[1], "version": words[2] if len(words) > 2 else ""}
    return out


def build_sh_value(text: str, name: str) -> str:
    m = re.search(rf'^{name}="?([^"\s]+)"?', text, re.M)
    return m.group(1) if m else ""


def manifest(repo: Path, commit: str, pkglist: str) -> dict:
    here = repo / "distro/archiso"
    build = (here / "build.sh").read_text()
    packages = {}
    for line in pkglist.splitlines():
        words = line.split()
        if len(words) == 2:
            packages[words[0]] = words[1]
    return {
        "citronos": {"commit": commit, "version": packages.get("citronos", "")},
        "archive": (repo / "distro/archive-date").read_text().strip(),
        "aur": pins(here / "aur-pins"),
        "blueferry": build_sh_value(build, "BLUEFERRY_TAG"),
        "hyprglass": {"version": build_sh_value(build, "HYPRGLASS_VERSION"),
                      "sha256": build_sh_value(build, "HYPRGLASS_SHA256"),
                      "hyprland": build_sh_value(build, "HYPRGLASS_HYPRLAND")},
        "packages": dict(sorted(packages.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--packages", required=True, type=Path)
    args = parser.parse_args()
    data = manifest(args.repo, args.commit, args.packages.read_text())
    if not data["packages"]:
        print("manifest.py: the package list is empty", file=sys.stderr)
        return 1
    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
