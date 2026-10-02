#!/usr/bin/env python3
"""Golden Gate default-desktop integrity checks.

The Dock, desktop entries, MIME defaults and ISO package set should describe one
coherent desktop rather than a mixture of Golden Gate and upstream GNOME apps.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
errors: list[str] = []

dock = (root / "shell/Dock.qml").read_text(encoding="utf-8")
desktop_dir = root / "apps/desktop"
desktop_ids = {p.stem for p in desktop_dir.glob("*.desktop")}

# Every Golden Gate app pinned in the Dock must have a desktop entry. Ignore the
# live-only installer distinction; it is still a real entry.
pinned_match = re.search(
    r"property var pinned:.*?concat\(\[(.*?)\]\)",
    dock,
    flags=re.S,
)
if not pinned_match:
    errors.append("Dock pinned-app model could not be parsed")
    pinned_ids: list[str] = []
else:
    pinned_ids = re.findall(r'"(org\.goldengate\.[A-Za-z0-9_-]+)"', pinned_match.group(1))
    # Installer sits in the prefix before concat().
    pinned_ids += re.findall(
        r'"(org\.goldengate\.Installer)"',
        dock[: pinned_match.start(1)],
    )

for app_id in sorted(set(pinned_ids)):
    if app_id not in desktop_ids:
        errors.append(f"Dock app has no Golden Gate desktop entry: {app_id}")

# Core first-party apps must remain native Golden Gate identities.
required_ids = {
    "org.goldengate.Calculator",
    "org.goldengate.Calendar",
    "org.goldengate.Clock",
    "org.goldengate.Files",
    "org.goldengate.Installer",
    "org.goldengate.Mail",
    "org.goldengate.Maps",
    "org.goldengate.Messages",
    "org.goldengate.Music",
    "org.goldengate.Notes",
    "org.goldengate.Photos",
    "org.goldengate.Settings",
    "org.goldengate.Software",
    "org.goldengate.Terminal",
    "org.goldengate.TextEdit",
    "org.goldengate.Weather",
    "org.goldengate.Web",
}
for app_id in sorted(required_ids - desktop_ids):
    errors.append(f"required Golden Gate desktop entry missing: {app_id}")

packages = {
    line.strip()
    for line in (root / "distro/archiso/packages.x86_64").read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
}
foreign_primary = {
    "nautilus", "gnome-software", "gnome-control-center", "gnome-clocks",
    "gnome-text-editor", "gnome-calendar", "loupe", "geary", "fractal",
    "firefox", "archinstall",
}
for package in sorted(foreign_primary & packages):
    errors.append(f"foreign/replaced primary app returned to ISO: {package}")

# Desktop files may wrap a mature backend (Terminal -> Ghostty), but they must
# not launch one of the replaced primary UIs.
blocked_exec = (
    "nautilus", "gnome-software", "gnome-control-center", "gnome-calendar",
    "geary", "fractal", "firefox", "gnome-text-editor", "gnome-clocks", "loupe",
)
for path in sorted(desktop_dir.glob("*.desktop")):
    data = path.read_text(encoding="utf-8").lower()
    for command in blocked_exec:
        if re.search(rf"^exec=.*\b{re.escape(command)}\b", data, flags=re.M):
            errors.append(f"{path.name} launches replaced primary UI {command}")


# Single-file native launchers must receive local filesystem paths, not plural
# URI lists their shell wrappers do not parse.
for desktop_name in ("org.goldengate.Files.desktop", "org.goldengate.TextEdit.desktop",
                     "org.goldengate.Photos.desktop", "org.goldengate.Music.desktop"):
    data = (desktop_dir / desktop_name).read_text(encoding="utf-8")
    exec_line = next((line for line in data.splitlines() if line.startswith("Exec=")), "")
    if "%U" in exec_line or "%F" in exec_line:
        errors.append(f"{desktop_name} uses a plural URI/file placeholder for a single-file launcher")

terminal = (desktop_dir / "org.goldengate.Terminal.desktop").read_text(encoding="utf-8")
if "StartupWMClass=com.mitchellh.ghostty" not in terminal:
    errors.append("Golden Gate Terminal lost its Ghostty window-class bridge")

install = (root / "scripts/install.sh").read_text(encoding="utf-8")
for mime, app_id in {
    "inode/directory": "org.goldengate.Files.desktop",
    "text/plain": "org.goldengate.TextEdit.desktop",
    "text/markdown": "org.goldengate.TextEdit.desktop",
    "application/json": "org.goldengate.TextEdit.desktop",
    "image/jpeg": "org.goldengate.Photos.desktop",
    "image/png": "org.goldengate.Photos.desktop",
    "image/webp": "org.goldengate.Photos.desktop",
    "image/gif": "org.goldengate.Photos.desktop",
    "image/tiff": "org.goldengate.Photos.desktop",
    "video/mp4": "org.goldengate.Photos.desktop",
    "video/quicktime": "org.goldengate.Photos.desktop",
    "video/webm": "org.goldengate.Photos.desktop",
    "audio/mpeg": "org.goldengate.Music.desktop",
    "audio/mp4": "org.goldengate.Music.desktop",
    "audio/flac": "org.goldengate.Music.desktop",
    "audio/ogg": "org.goldengate.Music.desktop",
    "audio/opus": "org.goldengate.Music.desktop",
    "audio/x-wav": "org.goldengate.Music.desktop",
    "x-scheme-handler/http": "org.goldengate.Web.desktop",
    "x-scheme-handler/https": "org.goldengate.Web.desktop",
}.items():
    token = f"{mime}={app_id}"
    if token not in install:
        errors.append(f"default application association missing: {token}")

session = (root / "distro/archiso/overlay/usr/local/bin/gg-session").read_text(encoding="utf-8")
for export in (
    "$HOME/.local/share/flatpak/exports/share",
    "/var/lib/flatpak/exports/share",
):
    if export not in session:
        errors.append(f"Flatpak desktop export missing from session: {export}")

applications = (root / "shell/Applications.qml").read_text(encoding="utf-8")
for needle in ("ScriptModel {", "DesktopEntries.applications.values"):
    if needle not in applications:
        errors.append(f"Applications launcher lost stable desktop-entry model: {needle}")
if "Quickshell.Services.DesktopEntries" in applications:
    errors.append("Applications uses obsolete/nonexistent DesktopEntries service import")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print("Default desktop: Golden Gate identities, MIME defaults and app discovery are coherent")
