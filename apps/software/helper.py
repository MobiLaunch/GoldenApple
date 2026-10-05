#!/usr/bin/env python3
"""Native CitronOS App Store backend backed by Flatpak/Flathub."""
from __future__ import annotations

import gzip
import json
import os
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET

REMOTE = "flathub"
REMOTE_URL = "https://dl.flathub.org/repo/flathub.flatpakrepo"
CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "golden-gate" / "app-store-catalog.json"


def emit(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}, separators=(",", ":")), flush=True)


def run(args: list[str], *, timeout: int | None = None, check: bool = False) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            args,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=check,
            env={**os.environ, "LC_ALL": "C"},
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        return subprocess.CompletedProcess(args, 124, stdout=(output + "\nSoftware source timed out.").strip())
    except OSError as exc:
        return subprocess.CompletedProcess(args, 127, stdout=str(exc))


def remote_exists() -> bool:
    p = run(["flatpak", "--user", "remotes", "--columns=name"])
    return any(line.strip() == REMOTE for line in p.stdout.splitlines())


def prepare(refresh: bool = True) -> tuple[bool, str]:
    if not shutil_which("flatpak"):
        return False, "Flatpak is not installed."

    if not remote_exists():
        p = run(
            ["flatpak", "remote-add", "--user", "--if-not-exists", REMOTE, REMOTE_URL],
            timeout=35,
        )
        if p.returncode != 0:
            return False, (p.stdout.strip().splitlines()[-1] if p.stdout.strip() else "Flathub could not be configured.")

    if refresh:
        p = run(["flatpak", "--user", "update", "--appstream", "-y"], timeout=60)
        # Cached metadata is still useful when refresh fails.
        if p.returncode != 0:
            return True, "Using cached catalog; the network refresh did not complete."
    return True, ""


def shutil_which(name: str) -> str | None:
    import shutil
    return shutil.which(name)


def appstream_files() -> list[pathlib.Path]:
    home = pathlib.Path.home()
    roots = [
        home / ".local/share/flatpak/appstream" / REMOTE,
        pathlib.Path("/var/lib/flatpak/appstream") / REMOTE,
    ]
    found: list[pathlib.Path] = []
    for root in roots:
        if not root.exists():
            continue
        found.extend(root.glob("*/active/appstream.xml.gz"))
        found.extend(root.glob("*/active/appstream.xml"))
    return sorted(found, key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)


def load_cached_catalog() -> list[dict[str, object]]:
    try:
        data = json.loads(CACHE.read_text(encoding="utf-8"))
        apps = data.get("apps", []) if isinstance(data, dict) else []
        return apps if isinstance(apps, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def save_cached_catalog(apps: list[dict[str, object]]) -> None:
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = CACHE.with_suffix(".tmp")
        tmp.write_text(json.dumps({"apps": apps}, separators=(",", ":")), encoding="utf-8")
        tmp.replace(CACHE)
    except OSError:
        # Catalog caching is resilience only; never fail the storefront because
        # the cache directory is read-only or temporarily unavailable.
        pass


def text_of(node: ET.Element | None, child: str, default: str = "") -> str:
    if node is None:
        return default
    found = node.find(child)
    if found is None or not found.text:
        return default
    return found.text.strip()


def icon_for(component: ET.Element, source: pathlib.Path) -> str:
    active = source.parent
    icons = component.findall("icon")
    # Prefer the cached 128/64px AppStream icons.
    for icon in icons:
        name = (icon.text or "").strip()
        if not name:
            continue
        if icon.attrib.get("type") == "cached":
            for size in ("128x128", "64x64"):
                candidate = active / "icons" / size / name
                if candidate.exists():
                    return str(candidate)
        if icon.attrib.get("type") == "local":
            candidate = pathlib.Path(name)
            if candidate.exists():
                return str(candidate)
    return ""


def installed_ids() -> set[str]:
    p = run(["flatpak", "--user", "list", "--app", "--columns=application"])
    return {x.strip() for x in p.stdout.splitlines() if x.strip()}


def update_ids() -> set[str]:
    p = run(["flatpak", "--user", "remote-ls", "--updates", "--app", "--columns=application", REMOTE])
    return {x.strip() for x in p.stdout.splitlines() if x.strip()}


def infer_categories(name: str, summary: str, app_id: str) -> list[str]:
    hay = f"{name} {summary} {app_id}".casefold()
    categories: list[str] = []
    rules = [
        ("Development", ("developer", "development", "code", "programming", "ide", "editor")),
        ("Graphics", ("graphics", "photo", "image", "drawing", "paint", "design")),
        ("AudioVideo", ("music", "audio", "video", "media", "podcast", "player")),
        ("Game", ("game", "gaming", "emulator")),
        ("Office", ("office", "document", "spreadsheet", "presentation", "productivity")),
        ("Utility", ("utility", "tool", "calculator", "archive", "file", "system")),
    ]
    for category, words in rules:
        if any(word in hay for word in words):
            categories.append(category)
    return categories


def fallback_catalog(installed: set[str], updates: set[str]) -> list[dict[str, object]]:
    p = run([
        "flatpak", "remote-ls", "--user", "--cached", "--app",
        "--columns=application,name,description", REMOTE,
    ], timeout=45)
    if p.returncode != 0:
        # A fresh remote may not have a complete cache yet; allow one normal
        # remote-ls pass before giving up.
        p = run([
            "flatpak", "remote-ls", "--user", "--app",
            "--columns=application,name,description", REMOTE,
        ], timeout=60)
    if p.returncode != 0:
        return []

    apps: list[dict[str, object]] = []
    for raw in p.stdout.splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        app_id = parts[0].strip() if parts else ""
        if not app_id or "." not in app_id:
            continue
        name = parts[1].strip() if len(parts) > 1 and parts[1].strip() else app_id.split(".")[-1]
        summary = parts[2].strip() if len(parts) > 2 else ""
        apps.append({
            "id": app_id,
            "name": name,
            "summary": summary,
            "categories": infer_categories(name, summary, app_id),
            "keywords": [],
            "project": "",
            "icon": "",
            "desktop": "",
            "installed": app_id in installed,
            "update": app_id in updates,
        })
    apps.sort(key=lambda a: str(a["name"]).casefold())
    return apps[:1800]


def catalog(*, refresh: bool = False) -> int:
    # A normal launch previously skipped AppStream refresh even on a completely
    # cold profile. That left a fresh install with a configured Flathub remote
    # but no local catalog, which looked like a network failure despite working
    # connectivity. Bootstrap metadata whenever no AppStream cache exists.
    okay, warning = prepare(refresh=refresh or not appstream_files())
    if not okay and not shutil_which("flatpak"):
        emit("error", message=warning or "Flatpak is not installed.")
        return 1

    installed = installed_ids()
    updates = update_ids()
    files = appstream_files()
    if not files:
        apps = fallback_catalog(installed, updates)
        if apps:
            save_cached_catalog(apps)
            emit("catalog", apps=apps, warning=warning or "Using Flatpak's cached catalog.")
            return 0
        cached = load_cached_catalog()
        if cached:
            emit("catalog", apps=cached, warning=warning or "Showing the last available App Store catalog while Flathub reconnects.")
            return 0
        emit("error", message=warning or "The Flathub catalog is not available yet. Try refreshing the App Store.")
        return 1

    source = files[0]
    try:
        if source.suffix == ".gz":
            with gzip.open(source, "rb") as fh:
                root = ET.parse(fh).getroot()
        else:
            root = ET.parse(source).getroot()
    except Exception as exc:
        apps = fallback_catalog(installed, updates)
        if apps:
            save_cached_catalog(apps)
            emit("catalog", apps=apps, warning=f"Using Flatpak's fallback catalog because AppStream could not be read: {exc}")
            return 0
        cached = load_cached_catalog()
        if cached:
            emit("catalog", apps=cached, warning="Showing the last available App Store catalog while local metadata is repaired.")
            return 0
        emit("error", message=f"The local App Store catalog could not be read: {exc}")
        return 1

    apps: list[dict[str, object]] = []

    for component in root.findall("component"):
        ctype = component.attrib.get("type", "")
        if ctype not in ("desktop-application", "desktop"):
            continue

        app_id = text_of(component, "id")
        name = text_of(component, "name")
        summary = text_of(component, "summary")
        if not app_id or not name:
            continue

        categories = [n.text.strip() for n in component.findall("./categories/category") if n.text]
        keywords = [n.text.strip() for n in component.findall("./keywords/keyword") if n.text]
        project = text_of(component, "project_group")
        launchable = component.find("launchable")
        desktop_id = (launchable.text or "").strip() if launchable is not None and launchable.text else ""

        # Flatpak AppStream IDs occasionally include a .desktop suffix.
        flatpak_id = app_id[:-8] if app_id.endswith(".desktop") else app_id

        apps.append(
            {
                "id": flatpak_id,
                "name": name,
                "summary": summary,
                "categories": categories,
                "keywords": keywords,
                "project": project,
                "icon": icon_for(component, source),
                "desktop": desktop_id,
                "installed": flatpak_id in installed,
                "update": flatpak_id in updates,
            }
        )

    apps.sort(key=lambda a: str(a["name"]).casefold())
    # Avoid making the QML engine swallow several megabytes of niche runtime
    # components while still providing a broad storefront.
    apps = apps[:1800]
    save_cached_catalog(apps)
    emit("catalog", apps=apps, warning=warning if okay else warning)
    return 0


def transaction(action: str, app_id: str) -> int:
    if not shutil_which("flatpak"):
        emit("error", id=app_id, message="Flatpak is not installed.")
        return 127
    if not app_id or any(ch.isspace() for ch in app_id):
        emit("error", id=app_id, message="The application identifier is invalid.")
        return 2

    if action == "launch":
        try:
            subprocess.Popen(
                ["flatpak", "run", app_id],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            emit("done", id=app_id, action=action)
            return 0
        except Exception as exc:
            emit("error", id=app_id, message=str(exc))
            return 1

    args = ["flatpak", "--user"]
    if action == "install":
        args += ["install", "-y", "--noninteractive", REMOTE, app_id]
    elif action == "update":
        args += ["update", "-y", "--noninteractive", app_id]
    elif action == "remove":
        args += ["uninstall", "-y", "--noninteractive", app_id]
    else:
        emit("error", id=app_id, message="Unsupported App Store operation.")
        return 2

    emit("progress", id=app_id, action=action, progress=0.08, message="Preparing…")
    proc = subprocess.Popen(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert proc.stdout is not None

    progress = 0.12
    last = ""
    for raw in proc.stdout:
        line = raw.strip()
        if not line:
            continue
        last = line
        lower = line.lower()
        if "required runtime" in lower or "looking for matches" in lower:
            progress = max(progress, 0.16)
        elif "installing" in lower or "updating" in lower:
            progress = min(0.88, progress + 0.12)
        elif "committing" in lower or "deploying" in lower:
            progress = max(progress, 0.90)
        emit("progress", id=app_id, action=action, progress=progress, message=line[:180])

    code = proc.wait()
    if code == 0:
        emit("done", id=app_id, action=action, progress=1.0)
        return 0

    emit("error", id=app_id, action=action, message=last or f"Flatpak exited with status {code}.")
    return code


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    cmd = sys.argv[1]
    if cmd == "catalog":
        return catalog(refresh=False)
    if cmd == "refresh":
        return catalog(refresh=True)
    if cmd in {"install", "update", "remove", "launch"} and len(sys.argv) == 3:
        return transaction(cmd, sys.argv[2])
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
