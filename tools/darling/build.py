#!/usr/bin/env python3
"""Prepare and build pinned Darling with Golden Gate's AppKit patches.

No packages are installed and the system Darling is never replaced by this tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "third_party/darling"


def run(args, *, cwd=None, env=None):
    print("+ " + " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def output(args, cwd):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def apply_patches(source: Path, lock: dict):
    """Accept the pinned pristine tree or an exactly patched tree; reject drift."""
    coco = source / "src/external/cocotron"
    for directory, expected in ((source, lock["darling_commit"]), (coco, lock["cocotron_commit"])):
        actual = output(["git", "rev-parse", "HEAD"], directory)
        if actual != expected:
            raise RuntimeError(f"Unexpected revision in {directory}: {actual}; expected {expected}")
    patches = []
    for item in lock["patches"]:
        patch = VENDOR / item["path"]
        if hashlib.sha256(patch.read_bytes()).hexdigest() != item["sha256"]:
            raise RuntimeError(f"Patch checksum mismatch: {patch.name}")
        patches.append(patch)
    # Validate all patches before changing anything. Use one apply operation so
    # an interrupted prepare does not leave only part of this patch series.
    forward = subprocess.run(["git", "apply", "--check", *map(str, patches)], cwd=coco, capture_output=True)
    if forward.returncode == 0:
        if output(["git", "status", "--porcelain"], coco):
            raise RuntimeError("Cocotron has local changes; use a dedicated clean checkout")
        run(["git", "apply", *patches], cwd=coco)
    else:
        reverse = subprocess.run(["git", "apply", "--reverse", "--check", *map(str, patches)], cwd=coco, capture_output=True)
        if reverse.returncode:
            raise RuntimeError("Cocotron is neither pristine nor the expected patched tree")
        expected = b"".join(p.read_bytes() for p in patches)
        # Compare reconstructed pristine blobs rather than requiring git diff's
        # formatting to match patch concatenation.
        paths = output(["git", "diff", "--name-only"], coco).splitlines()
        patch_paths = {line.split(" b/", 1)[1] for line in expected.decode().splitlines() if line.startswith("diff --git ")}
        if set(paths) != patch_paths or output(["git", "ls-files", "--others", "--exclude-standard"], coco):
            raise RuntimeError("Cocotron contains additional local changes")
        # Reverse-check catches nearby conflicts, but unrelated edits in the
        # same file also need checking: apply into a temporary pristine index.
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            env = {**os.environ, "GIT_INDEX_FILE": str(Path(temp) / "index")}
            subprocess.run(["git", "read-tree", "HEAD"], cwd=coco, env=env, check=True)
            subprocess.run(["git", "apply", "--cached", *map(str, patches)], cwd=coco, env=env, check=True)
            for path in paths:
                wanted = subprocess.check_output(["git", "show", ":" + path], cwd=coco, env=env)
                if (coco / path).read_bytes() != wanted:
                    raise RuntimeError(f"Additional edits in {path}; refusing to continue")
        print("Pinned patch series already applied.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "configure", "build", "stage"))
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build", type=Path)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        parser.error("This first milestone targets x86_64 Linux")
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.action != "prepare" and args.build is None:
        parser.error("--build is required")
    if args.action == "stage" and args.stage is None:
        parser.error("--stage is required")
    lock = json.loads((VENDOR / "source.lock.json").read_text())
    source = args.source.resolve()
    build = args.build.resolve() if args.build else None
    stage = args.stage.resolve() if args.stage else None
    if build == source or (build and source in build.parents):
        parser.error("Use a build directory outside the source tree")
    if stage and (stage == source or stage == build or source in stage.parents or (build and build in stage.parents)):
        parser.error("Use a separate staging directory")
    if not shutil.which("git"):
        raise RuntimeError("git is required")
    if subprocess.run(["git", "lfs", "version"], capture_output=True).returncode:
        raise RuntimeError("git-lfs is required to materialize Darling's source assets")
    if not source.exists():
        run(["git", "clone", "--no-checkout", lock["repository"], source])
        run(["git", "lfs", "install", "--local"], cwd=source)
        run(["git", "checkout", "--detach", lock["darling_commit"]], cwd=source)
    if output(["git", "rev-parse", "HEAD"], source) != lock["darling_commit"]:
        raise RuntimeError("Source revision differs from the lock; use a fresh checkout")
    # Never reset an existing checkout or discard local edits.
    dirty = output(["git", "status", "--porcelain", "--ignore-submodules=all"], source)
    if dirty:
        raise RuntimeError("Darling source has local changes; use a dedicated checkout")
    run(["git", "lfs", "install", "--local"], cwd=source)
    run(["git", "lfs", "pull"], cwd=source)
    run(["git", "submodule", "update", "--init", "--recursive"], cwd=source)
    run(["git", "submodule", "foreach", "--recursive", "git lfs pull"], cwd=source)
    apply_patches(source, lock)
    if args.action == "prepare":
        return
    for tool in ("cmake", "clang", "clang++", "ninja"):
        if not shutil.which(tool):
            raise RuntimeError(f"Missing build tool: {tool}; see docs/DARLING-GUI-M1.md")
    run(["cmake", "-S", source, "-B", build, "-G", "Ninja",
         "-DCMAKE_BUILD_TYPE=RelWithDebInfo", "-DTARGET_i386=OFF",
         "-DTARGET_x86_64=ON", "-DCOMPONENTS=cli,gui_frameworks",
         "-DENABLE_METAL=OFF", "-DCOMPILE_PY2_BYTECODE=OFF",
         "-DCMAKE_INSTALL_PREFIX=/usr/local"], cwd=source)
    if args.action == "configure":
        return
    run(["cmake", "--build", build, "--parallel", args.jobs])
    if args.action == "stage":
        stage.mkdir(parents=True, exist_ok=True)
        run(["cmake", "--install", build], env={**os.environ, "DESTDIR": str(stage)})
        (stage / "golden-gate-darling-build.json").write_text(json.dumps(lock, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Darling build failed: {error}", file=sys.stderr)
        sys.exit(1)
