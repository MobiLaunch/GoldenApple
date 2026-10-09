#!/usr/bin/env python3
"""Golden Gate app-icon curator: approved macOS-style icons ONLY in Launchpad.

The resolver runs after app installation and watches desktop-entry directories.
Only first-party GoldenGate artwork and matched open-source WhiteSur art qualify.
A missing match hides an app from Launchpad, NEVER removes the installed app.
Does not run upstream scripts or trust the Icon= path supplied by a .desktop.
"""
from __future__ import annotations

import configparser
import ctypes
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import shutil
import stat
import sys
import tarfile
import tempfile
import time
import urllib.request

HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "golden-gate"
SYSTEM_DATA = [Path(x) for x in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if x]
DESKTOP_DIRS = [DATA / "applications", DATA / "flatpak/exports/share/applications",
                Path("/var/lib/flatpak/exports/share/applications"),
                *(p / "applications" for p in SYSTEM_DATA)]
MANIFEST = CACHE / "launchpad-icons.json"
SOURCES = CACHE / "icon-packs/whitesur"
LICENSE_PATH = SOURCES / "COPYING"
INDEX = SOURCES / "index.json"
# Verified open-source upstream, pinned to a release instead of tracking master.
UPSTREAM_COMMIT = "73d8040da51a9ed74e47c7366e7e9ff437601a5c"
UPSTREAM = "https://codeload.github.com/vinceliuice/WhiteSur-icon-theme/tar.gz/" + UPSTREAM_COMMIT
SOURCE_URL = "https://github.com/vinceliuice/WhiteSur-icon-theme"
VERSION = "2026-09-10@" + UPSTREAM_COMMIT
ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,190}$")
SAFE_ART = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._+@-]{0,190}\.svg$")
GENERIC = {"application-x-executable", "application-default-icon", "application-x-desktop",
           "applications-other", "start-here", "unknown", "preferences-system",
           "image-missing", "package-x-generic", "org.freedesktop.application"}
FIRST_PARTY = "org.goldengate."
MAX_DOWNLOAD = 36 * 1024 * 1024
MAX_SVG = 2 * 1024 * 1024


def data_dirs():
    return list(dict.fromkeys(DESKTOP_DIRS))


def emit(**status):
    print(json.dumps(status, ensure_ascii=False), flush=True)


def atomic_write(path: Path, payload: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".gg-icons-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def safe_art(data: bytes):
    # Only SVG from the allowlisted source paths; no external entity loader or
    # JavaScript execution, no embedded remote images/scripts.
    if len(data) > MAX_SVG or not data.lstrip().startswith((b"<svg", b"<?xml")):
        return False
    lower = data.lower()
    # SVG namespace URIs are NOT external fetches; do not reject legitimate
    # SVGs just because xmlns="http://www.w3.org/2000/svg" is present.
    refs = re.findall(rb"(?:href|src)\s*=\s*['\"]([^'\"]+)['\"]", lower)
    return (b"<svg" in lower and b"<script" not in lower
            and b"<!doctype" not in lower and b"<!entity" not in lower
            and b"<foreignobject" not in lower and b"javascript:" not in lower
            and all(not ref.startswith((b"http:", b"https:", b"file:"))
                    and (not ref.startswith(b"data:") or
                         ref.startswith((b"data:image/png;base64,", b"data:image/jpeg;base64,")))
                    for ref in refs)
            and b"url(http" not in lower and b"url(https" not in lower)


def bootstrap():
    """Download source art once, extract icon SVGs, keep GPL-3 license.

    Does NOT execute downloaded code. Symlinks are resolved from tar headers
    only if they point at another SVG inside the verified source app directory.
    Any failure leaves the previously installed icon index unchanged.
    """
    if INDEX.is_file() and LICENSE_PATH.is_file():
        return True
    CACHE.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(
            UPSTREAM, headers={"User-Agent": "GoldenGate-IconResolver/1.0"}), timeout=25) as response:
        chunks = []
        received = 0
        while block := response.read(256 * 1024):
            received += len(block)
            if received > MAX_DOWNLOAD:
                raise ValueError("Open-source icon archive exceeds 36 MB")
            chunks.append(block)
    files = {}
    links = {}
    license_bytes = None
    with tarfile.open(fileobj=io.BytesIO(b"".join(chunks)), mode="r:gz") as tf:
        for member in tf:
            parts = PurePosixPath(member.name).parts
            if len(parts) < 2:
                continue
            rel = PurePosixPath(*parts[1:])
            if str(rel) == "COPYING" and member.isfile():
                license_bytes = tf.extractfile(member).read(128_000)
            # WhiteSur's full-size application art and exact icon aliases.
            if not (len(rel.parts) == 4 and rel.parts[0] in ("src", "links")
                    and rel.parts[1] == "apps" and rel.parts[2] == "scalable"
                    and SAFE_ART.fullmatch(rel.name)):
                continue
            key = str(rel)
            if member.isfile() and member.size <= MAX_SVG:
                svg = tf.extractfile(member).read(MAX_SVG + 1)
                if safe_art(svg):
                    files[key] = svg
            elif member.issym():
                links[key] = member.linkname
    if not license_bytes or b"GNU GENERAL PUBLIC LICENSE" not in license_bytes:
        raise ValueError("Icon pack is missing its published GPL license")
    # WhiteSur uses relative symlinks under links/apps/scalable. Accept only
    # direct links whose eventual bytes are already validated in src/apps/scalable.
    def follow(key):
        seen = set()
        while key in links and key not in seen:
            seen.add(key)
            raw = PurePosixPath(links[key])
            base = list(PurePosixPath(key).parent.parts)
            parts = list(base) if not raw.is_absolute() else []
            if raw.is_absolute():
                return None
            for part in raw.parts:
                if part == "..":
                    if not parts:
                        return None
                    parts.pop()
                elif part not in ("", "."):
                    parts.append(part)
            key = "/".join(parts)
        return files.get(key)
    usable = {}
    for key, blob in files.items():
        usable[PurePosixPath(key).name[:-4]] = blob
    for key in links:
        b = follow(key)
        if b:
            usable[PurePosixPath(key).name[:-4]] = b
    if not usable:
        raise ValueError("No approved macOS-style application SVGs found")
    stage = Path(tempfile.mkdtemp(prefix=".whitesur-stage-", dir=CACHE))
    try:
        folder = stage / "svg"
        folder.mkdir()
        record = {}
        for name, blob in usable.items():
            if not ID.fullmatch(name):
                continue
            digest = hashlib.sha256(blob).hexdigest()
            (folder / (name + ".svg")).write_bytes(blob)
            record[name] = {"file": name + ".svg", "sha256": digest}
        if not record:
            raise ValueError("No validated application icons")
        (stage / "index.json").write_text(json.dumps({"version": VERSION, "source": SOURCE_URL,
                                                      "icons": record}, sort_keys=True))
        (stage / "COPYING").write_bytes(license_bytes)
        SOURCES.parent.mkdir(parents=True, exist_ok=True)
        if SOURCES.exists():
            shutil.rmtree(SOURCES)
        os.replace(stage, SOURCES)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return True


def pack_index():
    try:
        obj = json.loads(INDEX.read_text(encoding="utf-8"))
        if obj.get("version") != VERSION:
            return {}
        icons = obj.get("icons", {})
        if not isinstance(icons, dict):
            return {}
        # The installed index is a cache, not an executable manifest: reject
        # entries that point outside its own validated SVG directory.
        return {key: value for key, value in icons.items()
                if ID.fullmatch(str(key)) and isinstance(value, dict)
                and value.get("file") == key + ".svg"
                and isinstance(value.get("sha256"), str)
                and re.fullmatch(r"[0-9a-f]{64}", value["sha256"])}
    except (OSError, ValueError, AttributeError):
        return {}


def app_entries():
    """Parse desktop entries with XDG user override precedence."""
    entries = {}
    for folder in data_dirs():
        if not folder.is_dir():
            continue
        for file in sorted(folder.glob("*.desktop")):
            if not ID.fullmatch(file.stem) or file.stem in entries:
                continue
            cfg = configparser.ConfigParser(interpolation=None, strict=False)
            cfg.optionxform = str
            try:
                cfg.read(file, encoding="utf-8")
            except (OSError, UnicodeError, configparser.Error):
                continue
            if not cfg.has_section("Desktop Entry"):
                continue
            g = cfg["Desktop Entry"]
            entries[file.stem] = {"id": file.stem, "name": g.get("Name", file.stem),
                                  "icon": g.get("Icon", ""), "hidden": g.get("Hidden", "false").lower() == "true",
                                  "noDisplay": g.get("NoDisplay", "false").lower() == "true",
                                  "desktop": str(file)}
    return entries


def theme_icon_names():
    """Recognize only icons actually present in the GoldenGate THEME, not its parents."""
    icons = {}
    for base in [DATA, *SYSTEM_DATA]:
        for dir_ in (base / "icons/GoldenGate/scalable/apps",
                     base / "icons/GoldenGate/512x512/apps"):
            if not dir_.is_dir():
                continue
            for file in dir_.iterdir():
                if file.suffix not in (".svg", ".png") or not ID.fullmatch(file.stem):
                    continue
                if file.is_file() and file.stem not in icons:
                    icons[file.stem] = str(file)
    return icons


def key_candidates(entry):
    ident = entry["id"]
    icon = entry["icon"]
    out = []
    for key in (ident, icon, ident.removesuffix(".desktop"),
                ident.lower(), icon.lower()):
        if not key or "/" in key or "\\" in key or key in GENERIC or not ID.fullmatch(key):
            continue
        if key not in out:
            out.append(key)
    return out


def sync(*, network=False, app_id=""):
    if network:
        try:
            bootstrap()
        except Exception as exc:
            # All first-party icons still work when offline; don't block apps.
            emit(event="pack-unavailable", reason=str(exc)[:160])
    upstream = pack_index()
    available = theme_icon_names()
    selected = {}
    copied = 0
    for item in app_entries().values():
        if item["hidden"] or item["noDisplay"]:
            continue
        app_id = item["id"]
        # Real Mac applications installed through Golden Gate's Darling
        # App Store have their OWN ICNS-derived PNG, not WhiteSur artwork.
        # These count as matching macOS icons only when the generated desktop
        # entry points to the exact, app-ID-specific image we extracted.
        if app_id.startswith("gg-mac-"):
            token = app_id[7:]
            owned = DATA / "golden-gate/mac-icons" / (token + ".png")
            try:
                if token and ID.fullmatch(token) and item["icon"] == str(owned) \
                        and owned.is_file() and 0 < owned.stat().st_size < 12 * 1024 * 1024:
                    with owned.open("rb") as f:
                        if f.read(8) == b"\x89PNG\r\n\x1a\n":
                            selected[app_id] = {"icon": str(owned), "source": "NativeMacApp"}
                            continue
            except OSError:
                pass
        # Keep first-party assets from GoldenGate, never replace them with a
        # downloaded Mac art that might not match the native application.
        if app_id.startswith(FIRST_PARTY):
            for key in key_candidates(item):
                if key in available:
                    selected[app_id] = {"icon": available[key], "source": "GoldenGate"}
                    break
            continue
        match = next((k for k in key_candidates(item) if k in upstream), None)
        if match:
            path = SOURCES / "svg" / upstream[match]["file"]
            try:
                if path.is_file():
                    art = path.read_bytes()
                    if not safe_art(art) or hashlib.sha256(art).hexdigest() != upstream[match]["sha256"]:
                        continue
                    selected[app_id] = {"icon": str(path), "source": "WhiteSur", "matched": match}
                    copied += 1
                    continue
            except OSError:
                pass
        # Local GoldenGate artwork explicitly names this app/icon: approved.
        # Do not confuse an OS generic icon or inherited Adwaita icon with a
        # curated GoldenGate app icon.
        for key in key_candidates(item):
            if key in available:
                selected[app_id] = {"icon": available[key], "source": "GoldenGate"}
                break
    payload = json.dumps({"version": 1, "source": SOURCE_URL,
                          "apps": selected}, ensure_ascii=False, sort_keys=True).encode()
    if not MANIFEST.is_file() or MANIFEST.read_bytes() != payload:
        atomic_write(MANIFEST, payload)
    emit(event="synced", visible=len(selected), matchedOpenSource=copied,
         hidden=max(0, len(app_entries())-len(selected)), manifest=str(MANIFEST),
         requested=app_id, matched=app_id in selected if app_id else None)
    return selected


def watch():
    """inotify desktop install directories, with a slow fallback re-scan."""
    sync(network=True)
    last_bootstrap = time.monotonic()
    libc = ctypes.CDLL(None, use_errno=True)
    init = libc.inotify_init1
    init.argtypes = [ctypes.c_int]
    init.restype = ctypes.c_int
    fd = init(os.O_NONBLOCK | os.O_CLOEXEC)
    if fd >= 0:
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
    dirs = data_dirs()
    last_dirs = set()
    try:
        while True:
            if fd >= 0:
                for d in dirs:
                    if d.is_dir() and str(d) not in last_dirs:
                        libc.inotify_add_watch(fd, os.fsencode(d),
                                                0x00000100 | 0x00000080 | 0x00000008 |
                                                0x00000200 | 0x00000040)
                        last_dirs.add(str(d))
                ready, _, _ = select.select([fd], [], [], 300)
                if ready:
                    try:
                        os.read(fd, 128 * 1024)
                    except BlockingIOError:
                        pass
                    time.sleep(0.6)  # installers frequently write multiple .desktop files
            else:
                time.sleep(60)
            # An offline first boot is normal. Retry the *pinned* open-source
            # source periodically when the connection appears, without making
            # any network calls in the interactive Launchpad thread.
            if not INDEX.is_file() and time.monotonic() - last_bootstrap >= 300:
                sync(network=True)
                last_bootstrap = time.monotonic()
            else:
                sync()
    finally:
        if fd >= 0:
            os.close(fd)


def main(args):
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / ".icon-resolver.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args and args[0] == "sync" and len(args) <= 2:
            sync(app_id=args[1] if len(args) == 2 else "")
        elif args and args[0] == "bootstrap" and len(args) <= 2:
            sync(network=True, app_id=args[1] if len(args) == 2 else "")
        elif args == ["watch"]:
            # Do not hold the same lock while sleeping: store installers also
            # need to sync. The watcher sync uses the same atomic manifest.
            fcntl.flock(lock, fcntl.LOCK_UN)
            watch()
        else:
            emit(error="usage: icon-resolver.py sync|bootstrap [APP_ID]|watch")
            return 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError, tarfile.TarError, urllib.error.URLError) as exc:
        emit(event="error", error=str(exc)[:250])
        raise SystemExit(1)
