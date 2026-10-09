#!/usr/bin/env python3
"""Golden Gate Settings: freedesktop MIME defaults and XDG login items.

No shell commands, desktop-file execution, or arbitrary file paths from the UI.
"""
from __future__ import annotations

import configparser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}\.desktop$")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
DATA = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
SYSTEM_DATA = [Path(p) for p in (os.environ.get("XDG_DATA_DIRS") or
    "/usr/local/share:/usr/share:/var/lib/flatpak/exports/share").split(":") if p]
SYSTEM_CONFIG = [Path(p) for p in (os.environ.get("XDG_CONFIG_DIRS") or
    "/etc/xdg").split(":") if p]
LOGIN = CONFIG / "autostart"
GROUP = "Desktop Entry"
CATEGORIES = {
    "Browser": "x-scheme-handler/https",
    "Email": "x-scheme-handler/mailto",
    "Text Documents": "text/plain",
    "Photos": "image/png",
    "Video": "video/mp4",
    "Archive Utility": "application/zip",
    "File Manager": "inode/directory",
}


def reply(ok=True, **data):
    print(json.dumps({"ok": ok, **data}, ensure_ascii=False))
    return 0 if ok else 1


def config(path: Path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if path.is_file() and path.stat().st_size < 1024 * 1024:
        try:
            parser.read(path, encoding="utf-8")
        except (configparser.Error, UnicodeError):
            pass
    return parser


def available():
    result = {}
    for base in [DATA, *SYSTEM_DATA]:
        folder = base / "applications"
        if not folder.is_dir():
            continue
        for file in sorted(folder.glob("*.desktop")):
            if not ID.fullmatch(file.name) or file.name in result:
                continue
            row = config(file)
            if not row.has_section(GROUP):
                continue
            opt = row[GROUP]
            if opt.get("Hidden") == "true" or opt.get("NoDisplay") == "true":
                continue
            result[file.name] = {
                "id": file.name, "name": opt.get("Name", file.stem),
                "mime": opt.get("MimeType", "").split(";"),
                "source": str(file),
            }
    return result


def defaults():
    apps = available()
    out = []
    for name, mime in CATEGORIES.items():
        proc = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True,
                              text=True, timeout=8)
        current = proc.stdout.strip() if proc.returncode == 0 else ""
        choices = [{"id": a["id"], "name": a["name"]} for a in apps.values()
                   if mime in a["mime"]]
        if current and current not in {c["id"] for c in choices}:
            choices.insert(0, {"id": current, "name": current.replace(".desktop", "")})
        choices.sort(key=lambda x: x["name"].lower())
        out.append({"title": name, "mime": mime, "current": current, "choices": choices})
    return out


def set_default(mime, desktop_id):
    if mime not in CATEGORIES.values() or not ID.fullmatch(desktop_id):
        raise ValueError("Not an allowed file association or application.")
    apps = available()
    if desktop_id not in apps or mime not in apps[desktop_id]["mime"]:
        raise ValueError("This application does not advertise support for that file type.")
    subprocess.run(["xdg-mime", "default", desktop_id, mime], check=True, timeout=10)


def installed_login_entries():
    """User overrides take precedence over system-wide XDG autostart entries."""
    found = {}
    for folder in [LOGIN, *(base / "autostart" for base in SYSTEM_CONFIG)]:
        if not folder.is_dir():
            continue
        for file in sorted(folder.glob("*.desktop")):
            if not ID.fullmatch(file.name) or file.name in found:
                continue
            data = config(file)
            if not data.has_section(GROUP):
                continue
            row = data[GROUP]
            found[file.name] = {
                "id": file.name, "name": row.get("Name", file.stem),
                "enabled": row.get("Hidden", "false").lower() != "true",
                "source": "User" if folder == LOGIN else "System",
            }
    return sorted(found.values(), key=lambda x: x["name"].lower())


def atomic(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError("Refusing a symbolic-link login item.")
    fd, name = tempfile.mkstemp(prefix=".login-item-", dir=path.parent)
    try:
        os.fchmod(fd, 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def toggle_login(desktop_id, on):
    if not ID.fullmatch(desktop_id) or type(on) is not bool:
        raise ValueError("Invalid login-item request.")
    path = LOGIN / desktop_id
    if on and not path.is_file():
        app = available().get(desktop_id)
        if not app:
            raise ValueError("This application is not installed or available.")
        source = Path(app["source"])
        atomic(path, source.read_text(encoding="utf-8"))
    else:
        row = config(path)
        if not row.has_section(GROUP):
            row.add_section(GROUP)
        row[GROUP]["Hidden"] = "false" if on else "true"
        from io import StringIO
        out = StringIO()
        row.write(out)
        atomic(path, out.getvalue())


def main(args):
    try:
        if args == ["defaults"]:
            return reply(rows=defaults())
        if len(args) == 3 and args[0] == "set-default":
            set_default(args[1], args[2])
            return reply(rows=defaults())
        if args == ["login-items"]:
            return reply(rows=installed_login_entries())
        if args == ["available"]:
            return reply(rows=[{"id": a["id"], "name": a["name"]}
                               for a in available().values()])
        if len(args) == 3 and args[0] == "toggle-login":
            if args[2] not in ("true", "false"):
                raise ValueError("Login item state must be true or false.")
            toggle_login(args[1], args[2] == "true")
            return reply(rows=installed_login_entries())
        raise ValueError("Usage: app-preferences.py defaults|set-default MIME ID|login-items|available|toggle-login ID BOOL")
    except (OSError, ValueError, subprocess.SubprocessError, UnicodeError) as exc:
        return reply(False, error=str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
