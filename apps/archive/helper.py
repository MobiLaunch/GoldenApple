#!/usr/bin/env python3
"""CitronOS Archive Utility backend: inspect, extract and create ZIP/tar archives.

Operations emit JSON lines for the QML front end; work runs outside the UI.
Extraction never follows archive links, never overwrites a destination, and
commits a completed directory atomically only after successful validation.
"""
from __future__ import annotations

import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import zipfile

MAX_ENTRIES = 100_000
MAX_UNPACKED = 8 * (1024 ** 3)
MAX_SINGLE = 4 * (1024 ** 3)
MAX_RATIO = 1000
CHUNK = 1024 * 1024
TAR_ENDINGS = (".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".tbz", ".tar")


class ArchiveError(Exception):
    pass


def emit(event: str, **detail: object) -> None:
    print(json.dumps({"event": event, **detail}, ensure_ascii=False), flush=True)


def archive_kind(path: Path) -> str:
    lower = path.name.lower()
    if lower.endswith((".zip", ".cbz")):
        return "zip"
    if lower.endswith(TAR_ENDINGS):
        return "tar"
    raise ArchiveError("Supported archives: ZIP, CBZ, TAR, TAR.GZ, TAR.BZ2 and TAR.XZ.")


def base_name(path: Path) -> str:
    lower = path.name.lower()
    for ext in (".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".txz", ".tbz2", ".tbz", ".zip", ".cbz", ".tar"):
        if lower.endswith(ext):
            return path.name[:-len(ext)] or "Extracted"
    return path.stem or "Extracted"


def safe_name(raw: str) -> tuple[str, ...]:
    """Archive members must remain beneath their assigned extraction directory."""
    if not isinstance(raw, str) or not raw or "\0" in raw:
        raise ArchiveError("The archive contains an invalid filename.")
    # Treat Windows separators as separators too; don't allow drive names or UNC.
    if raw.startswith(("/", "\\")) or re.match(r"^[a-zA-Z]:", raw):
        raise ArchiveError("The archive contains an absolute filename.")
    raw = raw.replace("\\", "/")
    parts = PurePosixPath(raw).parts
    if not parts or any(p in (".", "..", "") for p in raw.split("/") if p != ""):
        raise ArchiveError("The archive contains a path that leaves the extraction folder.")
    if len(parts) > 40 or any(len(p) > 240 or ":" in p for p in parts):
        raise ArchiveError("The archive has an unsafe or excessively long path.")
    return parts


def members(path: Path) -> list[tuple[str, bool, int, object]]:
    if not path.is_file():
        raise ArchiveError("This archive no longer exists.")
    result = []
    seen: dict[str, bool] = {}
    total = 0
    kind = archive_kind(path)
    try:
        with (zipfile.ZipFile(path) if kind == "zip" else tarfile.open(path, "r:*")) as archive:
            items = archive.infolist() if kind == "zip" else archive.getmembers()
            if len(items) > MAX_ENTRIES:
                raise ArchiveError("Archive contains too many files.")
            for item in items:
                name = item.filename if kind == "zip" else item.name
                parts = safe_name(name.rstrip("/"))
                is_dir = item.is_dir() if kind == "zip" else item.isdir()
                if kind == "zip":
                    mode = (item.external_attr >> 16) & 0xFFFF
                    file_type = stat.S_IFMT(mode)
                    if file_type not in (0, stat.S_IFDIR if is_dir else stat.S_IFREG):
                        raise ArchiveError("Archive contains a link or special file; extraction was blocked.")
                    size = item.file_size
                    if not is_dir and size > 64 * 1024 * 1024 and size / max(1, item.compress_size) > MAX_RATIO:
                        raise ArchiveError("Archive has a suspicious compression ratio.")
                else:
                    if not (item.isdir() or item.isfile()):
                        raise ArchiveError("Archive contains a link or special file; extraction was blocked.")
                    size = item.size
                if size < 0 or size > MAX_SINGLE:
                    raise ArchiveError("Archive member exceeds the size limit.")
                total += size
                if total > MAX_UNPACKED:
                    raise ArchiveError("Archive expands beyond the 8 GB safety limit.")
                canonical = "/".join(parts).casefold()
                if canonical in seen and not (is_dir and seen[canonical]):
                    raise ArchiveError("Archive has duplicate or conflicting filenames.")
                seen[canonical] = is_dir
                result.append(("/".join(parts), is_dir, size, item))
    except (zipfile.BadZipFile, tarfile.TarError, EOFError, OSError) as exc:
        raise ArchiveError(f"Cannot read archive: {exc}") from exc
    return result


def unique_destination(folder: Path, name: str) -> Path:
    path = folder / name
    if not path.exists() and not path.is_symlink():
        return path
    for i in range(2, 10000):
        option = folder / f"{name} {i}"
        if not option.exists() and not option.is_symlink():
            return option
    raise ArchiveError("There are too many similarly named extracted folders.")


def inspect(path: Path) -> None:
    records = members(path)
    shown = [{"name": name, "folder": folder, "size": size} for name, folder, size, _ in records[:5000]]
    emit("done", ok=True, mode="inspect", archive=str(path), kind=archive_kind(path),
         entries=shown, count=len(records), totalSize=sum(x[2] for x in records),
         truncated=len(records) > len(shown))


def extract(path: Path, destination: Path | None = None) -> None:
    records = members(path)  # Validate *before* touching the destination.
    parent = destination if destination else path.parent
    if not parent.is_dir():
        raise ArchiveError("Choose an existing destination folder.")
    stage = Path(tempfile.mkdtemp(prefix=".gg-extract-", dir=parent))
    try:
        kind = archive_kind(path)
        with (zipfile.ZipFile(path) if kind == "zip" else tarfile.open(path, "r:*")) as archive:
            for index, (name, folder, size, member) in enumerate(records):
                target = stage.joinpath(*PurePosixPath(name).parts)
                if folder:
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    # xb refuses collisions; all content is inside a private stage.
                    source = archive.open(member) if kind == "zip" else archive.extractfile(member)
                    if source is None:
                        raise ArchiveError("Could not read a member in this archive.")
                    copied = 0
                    with source, target.open("xb") as out:
                        while True:
                            chunk = source.read(CHUNK)
                            if not chunk:
                                break
                            copied += len(chunk)
                            if copied > size or copied > MAX_SINGLE:
                                raise ArchiveError("An archive member expanded past its advertised size.")
                            out.write(chunk)
                    if copied != size:
                        raise ArchiveError("An archive member had an unexpected size.")
                    target.chmod(0o644)
                if index % 32 == 0 or index == len(records) - 1:
                    emit("progress", completed=index + 1, total=len(records))
        # Exclusive folder rename on normal Linux filesystems, with private
        # name and no overwriting; recover cleanly if another process wins.
        for i in range(1, 10000):
            dest = parent / (base_name(path) if i == 1 else f"{base_name(path)} {i}")
            try:
                if dest.exists() or dest.is_symlink():
                    continue
                os.rename(stage, dest)
                emit("done", ok=True, mode="extract", destination=str(dest), count=len(records))
                return
            except FileExistsError:
                continue
        raise ArchiveError("No safe destination folder name is available.")
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def create(paths: list[Path]) -> None:
    if not paths:
        raise ArchiveError("Select one or more items to compress.")
    resolved = [p.absolute() for p in paths]
    if any(not p.exists() or p.is_symlink() for p in resolved):
        raise ArchiveError("Cannot compress missing items or symbolic links.")
    if len({str(p) for p in resolved}) != len(resolved):
        raise ArchiveError("The selection contains duplicate items.")
    parent = resolved[0].parent
    # Multiple selections can come from one Files window.
    if any(p.parent != parent for p in resolved):
        raise ArchiveError("All items must be in the same folder.")
    title = resolved[0].name if len(resolved) == 1 else "Archive"
    if title.lower().endswith(".zip"):
        title += " copy"
    output = unique_destination(parent, title + ".zip")
    fd, tempname = tempfile.mkstemp(prefix=".gg-compress-", suffix=".zip", dir=parent)
    os.close(fd)
    temp = Path(tempname)
    total = 0
    count = 0
    try:
        with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            for root in resolved:
                candidates = [root] if root.is_file() else [root, *sorted(root.rglob("*"))]
                for candidate in candidates:
                    if candidate.is_symlink():
                        raise ArchiveError("Symbolic links are not included in new archives.")
                    if not (candidate.is_file() or candidate.is_dir()):
                        raise ArchiveError("Cannot include device files or special files.")
                    name = "/".join((root.name,) + candidate.relative_to(root).parts)
                    if candidate.is_dir():
                        archive.writestr(name.rstrip("/") + "/", b"")
                    else:
                        total += candidate.stat().st_size
                        if total > MAX_UNPACKED:
                            raise ArchiveError("Selection exceeds the 8 GB compression limit.")
                        archive.write(candidate, arcname=name)
                    count += 1
                    if count > MAX_ENTRIES:
                        raise ArchiveError("Too many items to compress.")
                    if count % 32 == 0:
                        emit("progress", completed=count, total=0)
        # Exclusive final link: won't overwrite a newly created ZIP.
        os.link(temp, output)
        emit("done", ok=True, mode="create", destination=str(output), count=count)
    finally:
        temp.unlink(missing_ok=True)


def main(argv: list[str]) -> int:
    try:
        if not argv:
            raise ArchiveError("Usage: helper.py inspect|extract|create FILE [DESTINATION]")
        action, *args = argv
        if action == "inspect" and len(args) == 1:
            inspect(Path(args[0]).expanduser())
        elif action == "extract" and len(args) in (1, 2):
            extract(Path(args[0]).expanduser(), Path(args[1]).expanduser() if len(args) == 2 else None)
        elif action == "create" and args:
            create([Path(p).expanduser() for p in args])
        else:
            raise ArchiveError("Unrecognized archive operation.")
        return 0
    except (ArchiveError, OSError, RuntimeError, ValueError, zipfile.BadZipFile,
            tarfile.TarError, NotImplementedError) as exc:
        emit("done", ok=False, error=str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
