#!/usr/bin/env python3
"""Export a checksummed, standalone Arch source package build context.

This exports source and a recipe, never installs or packages Ubuntu binaries.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def export(destination, root=ROOT):
    root, destination = Path(root), Path(destination)
    lock_path = root / "third_party/darling/source.lock.json"
    lock_bytes = lock_path.read_bytes()
    lock = json.loads(lock_bytes)
    files = [lock_path, root / "tools/darling/build.py", root / "tools/darling/runtime.py"]
    vendor = root / "third_party/darling"
    for item in lock["patches"]:
        patch = vendor / item["path"]
        if vendor.resolve() not in patch.resolve().parents:
            raise ValueError("Patch path escapes the source bundle")
        if hashlib.sha256(patch.read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError(f"Patch checksum mismatch: {patch.name}")
        files.append(patch)
    # Stable archive contents and gzip timestamp make independent exports match.
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as tar:
            for path in sorted(files):
                body = path.read_bytes()
                info = tarfile.TarInfo("golden-gate-darling/" + str(path.relative_to(root)))
                info.size, info.mode = len(body), 0o644
                tar.addfile(info, io.BytesIO(body))
    archive = compressed.getvalue()
    recipe = (root / "tools/darling/arch/PKGBUILD.in").read_text()
    recipe = recipe.replace("@SOURCE_SHA256@", hashlib.sha256(archive).hexdigest())
    recipe = recipe.replace("@LOCK_ID@", hashlib.sha256(lock_bytes).hexdigest()[:12])
    if destination.exists():
        raise ValueError("Use a new export directory; existing files are preserved")
    destination.mkdir(parents=True)
    (destination / "golden-gate-darling-source.tar.gz").write_bytes(archive)
    (destination / "PKGBUILD").write_text(recipe)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        print(export(args.destination))
    except (OSError, ValueError) as error:
        parser.exit(1, f"Arch source export failed: {error}\n")


if __name__ == "__main__":
    main()
