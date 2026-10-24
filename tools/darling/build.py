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
import tempfile

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "third_party/darling"


def run(args, *, cwd=None, env=None, timeout=None):
    print("+ " + " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True, timeout=timeout)


def output(args, cwd):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def fetch_submodules(source, with_swift=False):
    # Check out pointers first. Fetching during smudge previously retried an
    # unavailable optional Swift LFS endpoint for almost two hours in CI.
    env = {**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"}
    paths = [line.split(" ", 1)[1] for line in output(
        ["git", "config", "--file", ".gitmodules", "--get-regexp", r"^submodule\..*\.path$"], source).splitlines()]
    paths = [p for p in paths if with_swift or p != "src/external/swift"]
    run(["git", "submodule", "update", "--init", "--recursive", "--", *paths],
        cwd=source, env=env, timeout=900)
    initialized = [source]
    for line in output(["git", "submodule", "status", "--recursive"], source).splitlines():
        if line.startswith("-"):
            continue
        path = line[1:].split()[1]
        if not with_swift and (path == "src/external/swift" or path.startswith("src/external/swift/")):
            continue
        initialized.append(source / path)
    for directory in initialized:
        if not output(["git", "lfs", "ls-files", "--name-only"], directory):
            continue
        # Explicit pulls materialize required assets. Connection stalls fail
        # promptly rather than silently leaving pointer text in the build.
        run(["git", "-c", "lfs.dialtimeout=15", "-c", "lfs.tlstimeout=15",
             "-c", "lfs.activitytimeout=30", "-c", "lfs.transfer.maxretries=1",
             "lfs", "pull"], cwd=directory, timeout=180)


def apply_patches(source: Path, lock: dict):
    """Preflight every repository before applying pinned patches; reject drift."""
    coco = source / "src/external/cocotron"
    repositories = {"darling": source, "cocotron": coco, "objc4": source / "src/external/objc4"}
    for name, directory in repositories.items():
        expected = lock[name + "_commit"]
        actual = output(["git", "rev-parse", "HEAD"], directory)
        if actual != expected:
            raise RuntimeError(f"Unexpected revision in {directory}: {actual}; expected {expected}")
    groups = {name: [] for name in repositories}
    for item in lock["patches"]:
        name = item.get("repository", "cocotron")
        if name not in groups:
            raise RuntimeError(f"Unknown patch repository: {name}")
        patch = VENDOR / item["path"]
        if VENDOR.resolve() not in patch.resolve().parents:
            raise RuntimeError("Patch path must stay inside third_party/darling")
        if hashlib.sha256(patch.read_bytes()).hexdigest() != item["sha256"]:
            raise RuntimeError(f"Patch checksum mismatch: {patch.name}")
        groups[name].append(patch)
    pending = []
    for name, directory in repositories.items():
        patches = groups[name]
        if not patches:
            if output(["git", "status", "--porcelain", "--ignore-submodules=all"], directory):
                raise RuntimeError(f"{name} contains local changes")
            continue
        forward = subprocess.run(["git", "apply", "--check", *map(str, patches)], cwd=directory, capture_output=True)
        if forward.returncode == 0:
            if output(["git", "status", "--porcelain", "--ignore-submodules=all"], directory):
                raise RuntimeError(f"{name} has local changes; use a dedicated clean checkout")
            pending.append((directory, patches))
            continue
        reverse = subprocess.run(["git", "apply", "--reverse", "--check", *map(str, patches)], cwd=directory, capture_output=True)
        if reverse.returncode:
            raise RuntimeError(f"{name} is neither pristine nor the expected patched tree")
        # Root patches can add files. Their untracked files must match the
        # expected series exactly; no other local files may be overwritten.
        paths = set(output(["git", "diff", "--name-only", "--ignore-submodules=all"], directory).splitlines())
        paths.update(output(["git", "ls-files", "--others", "--exclude-standard"], directory).splitlines())
        patch_paths = {line.split(" b/", 1)[1] for p in patches for line in p.read_text().splitlines()
                       if line.startswith("diff --git ")}
        if paths != patch_paths:
            raise RuntimeError(f"{name} contains additional local changes")
        # Reconstruct pristine blobs in a temporary index to catch unrelated
        # edits in files that still happen to pass a reverse-apply check.
        with tempfile.TemporaryDirectory() as temp:
            env = {**os.environ, "GIT_INDEX_FILE": str(Path(temp) / "index")}
            subprocess.run(["git", "read-tree", "HEAD"], cwd=directory, env=env, check=True)
            subprocess.run(["git", "apply", "--cached", *map(str, patches)], cwd=directory, env=env, check=True)
            for path in paths:
                wanted = subprocess.check_output(["git", "show", ":" + path], cwd=directory, env=env)
                if (directory / path).read_bytes() != wanted:
                    raise RuntimeError(f"Additional edits in {path}; refusing to continue")
        print(f"Pinned {name} patches already applied.", flush=True)
    applied = []
    try:
        for directory, patches in pending:
            run(["git", "apply", *patches], cwd=directory)
            applied.append((directory, patches))
    except subprocess.CalledProcessError:
        # git apply is atomic per repository. Roll back only our completed
        # groups; validation above has already ruled out local edits.
        for directory, patches in reversed(applied):
            run(["git", "apply", "--reverse", *patches], cwd=directory)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "configure", "build", "stage"))
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--build", type=Path)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--install-prefix", choices=("/usr", "/usr/local"), default="/usr/local")
    parser.add_argument("--with-swift", action="store_true", help="Fetch and install upstream prebuilt Swift assets")
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
    if stage and stage.exists() and any(stage.iterdir()):
        parser.error("Use an empty staging directory; stale runtime files must not satisfy validation")
    if not shutil.which("git"):
        raise RuntimeError("git is required")
    if subprocess.run(["git", "lfs", "version"], capture_output=True).returncode:
        raise RuntimeError("git-lfs is required to materialize Darling's source assets")
    if not source.exists():
        run(["git", "clone", "--no-checkout", lock["repository"], source], timeout=600)
        run(["git", "lfs", "install", "--local"], cwd=source)
        run(["git", "checkout", "--detach", lock["darling_commit"]], cwd=source,
            env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"}, timeout=120)
    if output(["git", "rev-parse", "HEAD"], source) != lock["darling_commit"]:
        raise RuntimeError("Source revision differs from the lock; use a fresh checkout")
    # Never reset an existing checkout or discard local edits.
    # apply_patches validates root changes as well as Cocotron. Root framework
    # patches are expected local modifications in a prepared checkout.
    run(["git", "lfs", "install", "--local"], cwd=source)
    fetch_submodules(source, args.with_swift)
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
         # Upstream's packaging flag also disables its install-time script
         # that shuts down host Darling sessions, even during DESTDIR staging.
         "-DDEBIAN_PACKAGING=ON",
         f"-DINSTALL_SWIFT_RUNTIME={'ON' if args.with_swift else 'OFF'}",
         f"-DCMAKE_INSTALL_PREFIX={args.install_prefix}"], cwd=source)
    if args.action == "configure":
        return
    run(["cmake", "--build", build, "--parallel", args.jobs])
    if args.action == "stage":
        stage.mkdir(parents=True, exist_ok=True)
        run(["cmake", "--install", build], env={**os.environ, "DESTDIR": str(stage)})
        provenance = {"schema": 1, "source_lock": lock, "install_prefix": args.install_prefix,
                      "host": {"system": platform.system(), "machine": platform.machine()},
                      "components": ["cli", "gui_frameworks"], "swift_runtime": args.with_swift}
        (stage / "golden-gate-darling-build.json").write_text(json.dumps(provenance, indent=2) + "\n")
        run([sys.executable, ROOT / "tools/darling/runtime.py", stage,
             "--install-prefix", args.install_prefix])


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"Darling build failed: {error}", file=sys.stderr)
        sys.exit(1)
