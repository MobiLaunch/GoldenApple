"""LCode projects: opening a folder, LCode's own data, the tree and search.

LCode keeps its data in .lcode/: project.json (toolchain, product type, app
identity, default run destination; committed) and userdata/state.json (open
tabs; git-ignored), the counterparts of an .xcodeproj and its xcuserdata.
Toolchains live in lcode_toolchains.py and templates in lcode_templates.py.
"""
from __future__ import annotations

import json
import os
import pathlib

import lcode_toolchains as toolchains
from lcode_templates import (HOST, TEMPLATES, TEMPLATE_INFO, application_id, author_name, bundle_identifier,  # noqa: F401
                             create_project, file_header, module_name, new_file_contents, slug_name, snake_name)
from lcode_toolchains import parse_diagnostic, parse_progress, strip_ansi  # noqa: F401

IGNORED_DIRS = {"build", "build-release", "target", "DerivedData", "node_modules", "__pycache__"}


def is_ignored(name: str) -> bool:
    return name.startswith(".") or name in IGNORED_DIRS


def read_json(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def open_project(raw: str, default_simulator: str = "lphone-16") -> dict:
    root = pathlib.Path(raw).expanduser().resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"“{raw}” is not a folder.")
    meta = read_json(root / ".lcode/project.json")
    toolchain = toolchains.detect(root, meta)
    info = toolchains.describe(toolchain, root)
    kind = meta.get("kind") or info["kind"]
    if toolchain == "python" and meta.get("display_name") and info["products"]:
        # A Python program has no product name of its own: use the app's name.
        info = dict(info, name=meta["display_name"], products=[meta["display_name"]])
    destination = meta.get("default_destination") or (default_simulator if kind == "app" and toolchain not in ("goldengate",) else HOST)
    return {
        "root": str(root),
        "name": info["name"],
        "toolchain": toolchain,
        "language": toolchains.NAMES.get(toolchain, ""),
        "isPackage": bool(toolchain),
        "kind": kind,
        "products": info["products"],
        "bundleId": meta.get("bundle_identifier", ""),
        "organization": meta.get("organization", ""),
        "displayName": meta.get("display_name") or info["name"],
        "version": meta.get("version", "1.0"),
        "meta": meta,
        "destination": destination,
        "state": read_json(root / ".lcode/userdata/state.json"),
    }


def save_meta(root: str, values: dict) -> dict:
    """Update .lcode/project.json (product type, identity, app settings)."""
    path = pathlib.Path(root) / ".lcode/project.json"
    meta = read_json(path)
    for k, v in values.items():
        if v is None:
            meta.pop(k, None)
        else:
            meta[k] = v
    write_json(path, meta)
    return meta


def save_state(root: str, state: dict) -> None:
    write_json(pathlib.Path(root) / ".lcode/userdata/state.json", state)


def tree(raw: str, limit: int = 20000) -> list[dict]:
    """Every file and folder under root (hidden and build folders skipped),
    folders first, then names case-insensitively, as a flat parent-linked list."""
    root = pathlib.Path(raw)
    out: list[dict] = []

    def walk(folder: pathlib.Path, depth: int) -> None:
        try:
            entries = [e for e in os.scandir(folder) if not is_ignored(e.name)]
        except OSError:
            return
        entries.sort(key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower()))
        for e in entries:
            if len(out) >= limit:
                return
            is_dir = e.is_dir(follow_symlinks=False)
            out.append({"path": e.path, "name": e.name, "dir": is_dir, "depth": depth, "parent": str(folder)})
            if is_dir:
                walk(pathlib.Path(e.path), depth + 1)

    walk(root, 0)
    return out


def tree_signature(raw: str) -> tuple:
    """Cheap change detector for the project tree: folder mtimes and names."""
    sig = []
    for dirpath, dirnames, filenames in os.walk(raw):
        dirnames[:] = sorted(d for d in dirnames if not is_ignored(d))
        try:
            sig.append((dirpath, os.stat(dirpath).st_mtime_ns))
        except OSError:
            pass
    return tuple(sig)


def files(raw: str, limit: int = 20000) -> list[str]:
    return [n["path"] for n in tree(raw, limit) if not n["dir"]]


# ------------------------------------------------------------------ search

def find(raw: str, query: str, case_sensitive: bool = False, max_results: int = 2000) -> list[dict]:
    """Plain-text search across project files: [{path, matches: [{line, column, text, start, length}]}]."""
    needle = query if case_sensitive else query.lower()
    out: list[dict] = []
    total = 0
    if not needle:
        return out
    for path in files(raw):
        try:
            if os.path.getsize(path) > 2 * 1024 * 1024:
                continue
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        matches = []
        for i, line in enumerate(text.splitlines()):
            hay = line if case_sensitive else line.lower()
            idx = hay.find(needle)
            if idx < 0:
                continue
            lead = len(line) - len(line.lstrip())
            matches.append({"line": i + 1, "column": idx + 1, "text": line.strip()[:240],
                            "start": max(0, idx - lead), "length": len(needle)})
            total += 1
            if total >= max_results:
                break
        if matches:
            out.append({"path": path, "matches": matches})
        if total >= max_results:
            break
    return out


