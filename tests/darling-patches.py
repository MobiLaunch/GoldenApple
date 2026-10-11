#!/usr/bin/env python3
"""Test application and drift protection using the actual pinned source blobs.

Usage: python3 tests/darling-patches.py /path/to/darling
The supplied checkout is read only. Every mutation uses a temporary repository.
"""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("darling_build", ROOT / "tools/darling/build.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = Path(sys.argv[1]).resolve()
lock = json.loads((ROOT / "third_party/darling/source.lock.json").read_text())


def git(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, stderr=subprocess.STDOUT)


def rejects(source, config, message):
    try:
        module.apply_patches(source, config)
    except RuntimeError:
        return
    raise AssertionError(message)


with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    coco = temp / "src/external/cocotron"
    coco.mkdir(parents=True)
    git(temp, "init", "-q")
    git(temp, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "baseline")
    git(coco, "init", "-q")
    paths = set()
    for patch in lock["patches"]:
        for line in (module.VENDOR / patch["path"]).read_text().splitlines():
            if line.startswith("diff --git "):
                paths.add(line.split(" b/", 1)[1])
    for path in paths:
        target = coco / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(git(source / "src/external/cocotron", "show", lock["cocotron_commit"] + ":" + path))
    git(coco, "add", ".")
    git(coco, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "pristine source blobs")
    config = copy.deepcopy(lock)
    config["darling_commit"] = git(temp, "rev-parse", "HEAD").decode().strip()
    config["cocotron_commit"] = git(coco, "rev-parse", "HEAD").decode().strip()
    module.apply_patches(temp, config)
    first_diff = git(coco, "diff")
    module.apply_patches(temp, config)
    assert git(coco, "diff") == first_diff, "second application must be idempotent"
    changed = coco / "AppKit/NSViewController.m"
    expected = changed.read_bytes()
    changed.write_bytes(expected + b"\n// unrelated local edit\n")
    rejects(temp, config, "same-file edits must be refused")
    assert changed.read_bytes().endswith(b"// unrelated local edit\n"), "local changes must be preserved"
    changed.write_bytes(expected)
    (coco / "unexpected.txt").write_text("local work")
    rejects(temp, config, "untracked edits must be refused")
    (coco / "unexpected.txt").unlink()
    bad = copy.deepcopy(config)
    bad["patches"][0]["sha256"] = "0" * 64
    rejects(temp, bad, "checksum mismatch must be refused")
    bad = copy.deepcopy(config)
    bad["cocotron_commit"] = "0" * 40
    rejects(temp, bad, "revision mismatch must be refused")
    git(coco, "restore", ".")
    # A partially applied series is refused instead of being silently completed.
    git(coco, "apply", str(module.VENDOR / lock["patches"][0]["path"]))
    rejects(temp, config, "partial patch series must be refused")
print("PASS: pinned patches apply atomically, are idempotent, reject drift, and preserve local edits")
