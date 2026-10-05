#!/usr/bin/env python3
"""Mac apps for the App Store: download them from their developers, install
them in ~/Applications, and open them with Darling (darlinghq.org), the
macOS translation layer.

Where the apps come from: the Homebrew Cask catalog (formulae.brew.sh), the
public list of Mac apps their developers ship as .dmg or .zip downloads, each
with its download address, version and checksum. Mac App Store apps are tied
to an Apple ID and encrypted, so they aren't offered.

What runs: Darling runs command-line programs well; its graphical support is
still experimental, so many apps won't open yet. This module says so plainly:
an app built only for Apple silicon is refused before anything is installed,
and when an app doesn't open, the reason (Darling's own output) is kept and
shown.

    macapps.py catalog [--refresh]   the catalog (slim, cached for a day)
    macapps.py all [--refresh]       catalog, installed apps and Darling's status at once
    macapps.py installed             what's in ~/Applications from here
    macapps.py status                is Darling installed?
    macapps.py install TOKEN         download, verify, install (progress as JSON lines)
    macapps.py open TOKEN            open with Darling; report if it didn't
    macapps.py remove TOKEN          uninstall
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.error
import urllib.request
import zipfile

CATALOG_URL = os.environ.get("GG_MAC_CATALOG_URL", "https://formulae.brew.sh/api/cask.json")
HOME = pathlib.Path.home()
CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "golden-gate"
DATA = pathlib.Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
APPLICATIONS = HOME / "Applications"
RECORD = DATA / "golden-gate" / "mac-apps.json"
ICONS = DATA / "golden-gate" / "mac-icons"
LOGS = CACHE / "mac-logs"
SLIM = CACHE / "mac-catalog.json"
USER_AGENT = "GoldenGate-AppStore/1.0 (+https://github.com/mobilaunch/goldenapple)"

# Mac apps people look for first; all of them free downloads from their developers.
FEATURED = ["iina", "coteditor", "netnewswire", "textmate", "hex-fiend", "skim", "keka",
            "bbedit", "imageoptim", "cyberduck", "macdown", "sequel-ace", "the-unarchiver",
            "appcleaner", "stats", "maccy"]


def emit(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}, separators=(",", ":")), flush=True)


# ---------------------------------------------------------------- catalog
def fetch(url: str, dest: pathlib.Path, progress=None, tries: int = 2) -> None:
    """Download url to dest (atomically), calling progress(done, total). A
    dropped connection is tried once more; a server's refusal says what it
    was (403, 404…), not just that it failed."""
    for attempt in range(tries):
        try:
            return _fetch(url, dest, progress)
        except urllib.error.HTTPError as exc:
            raise OSError(f"the server answered {exc.code} {exc.reason} for {urllib.parse.urlparse(url).netloc}") from exc
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            if attempt == tries - 1:
                reason = getattr(exc, "reason", exc)
                raise OSError(f"couldn't reach {urllib.parse.urlparse(url).netloc} ({reason})") from exc
            time.sleep(2)


def _fetch(url: str, dest: pathlib.Path, progress=None) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    tmp = dest.with_name(dest.name + ".part")
    with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "wb") as out:
        total = int(resp.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = resp.read(1 << 16)
            if not chunk:
                break
            out.write(chunk)
            done += len(chunk)
            if progress:
                progress(done, total)
    tmp.replace(dest)


def download_url(cask: dict) -> str:
    """The Intel (x86_64) download where the cask has one: Darling translates
    Intel Mac code, not Apple silicon's. Homebrew's variations name Intel
    builds without the arm64_ prefix (and its Linux builds, *_linux, aren't
    Mac apps at all)."""
    for key, var in (cask.get("variations") or {}).items():
        if not key.startswith("arm64") and "linux" not in key and isinstance(var, dict) and var.get("url"):
            return var["url"]
    return cask.get("url") or ""


def sha_for(cask: dict, url: str) -> str:
    for key, var in (cask.get("variations") or {}).items():
        if isinstance(var, dict) and var.get("url") == url and var.get("sha256"):
            return var["sha256"]
    return cask.get("sha256") or ""


def slim(cask: dict) -> dict | None:
    """The parts of a cask the store shows and installs, or None when it isn't
    an app we can install (no .app, a .pkg installer, Apple silicon only,
    withdrawn)."""
    if cask.get("deprecated") or cask.get("disabled"):
        return None
    apps = [a for art in cask.get("artifacts") or [] if isinstance(art, dict)
            for a in (art.get("app") or []) if isinstance(a, str)]
    if not apps:
        return None
    arch = (cask.get("depends_on") or {}).get("arch") or []
    if arch and all("arm" in str(a) for a in (arch if isinstance(arch, list) else [arch])):
        return None
    url = download_url(cask)
    path = urllib.parse.urlparse(url).path.lower()
    kind = "dmg" if path.endswith(".dmg") else "zip" if path.endswith(".zip") else ""
    if not kind:
        return None
    names = cask.get("name") or [cask.get("token", "")]
    return {
        "token": cask["token"], "name": names[0], "desc": cask.get("desc") or "",
        "homepage": cask.get("homepage") or "", "version": str(cask.get("version") or ""),
        "url": url, "sha256": sha_for(cask, url), "app": apps[0], "kind": kind,
        "checksum": bool(sha_for(cask, url)) and sha_for(cask, url) != "no_check",
        "minMacOS": min_macos(cask),
    }


def min_macos(cask: dict) -> str:
    """{"depends_on": {"macos": {">=": ["12"]}}} → "12"."""
    mac = (cask.get("depends_on") or {}).get("macos")
    if isinstance(mac, dict):
        for versions in mac.values():
            if isinstance(versions, list) and versions:
                return str(versions[0])
    return ""


def load_catalog(refresh: bool = False) -> list[dict]:
    fresh = SLIM.exists() and time.time() - SLIM.stat().st_mtime < 86400
    if fresh and not refresh:
        try:
            return json.loads(SLIM.read_text())
        except (OSError, ValueError):
            pass
    raw = CACHE / "cask.json"
    raw.parent.mkdir(parents=True, exist_ok=True)
    try:
        if CATALOG_URL.startswith("file://"):
            shutil.copyfile(urllib.parse.unquote(urllib.parse.urlparse(CATALOG_URL).path), raw)
        else:
            fetch(CATALOG_URL, raw)
        casks = json.loads(raw.read_text())
    except (OSError, ValueError) as exc:
        if SLIM.exists():
            return json.loads(SLIM.read_text())
        raise RuntimeError(f"The Mac app catalog couldn't be loaded ({exc}).") from exc
    out = [s for s in (slim(c) for c in casks if isinstance(c, dict) and c.get("token")) if s]
    out.sort(key=lambda s: s["name"].casefold())
    SLIM.parent.mkdir(parents=True, exist_ok=True)
    SLIM.write_text(json.dumps(out, separators=(",", ":")))
    raw.unlink(missing_ok=True)          # tens of megabytes; the slim list is all we keep
    return out


def find(token: str) -> dict:
    for c in load_catalog():
        if c["token"] == token:
            return c
    raise RuntimeError(f"“{token}” isn't in the Mac app catalog.")


# ---------------------------------------------------------------- the record
def records() -> dict:
    try:
        return json.loads(RECORD.read_text())
    except (OSError, ValueError):
        return {}


def save_records(data: dict) -> None:
    RECORD.parent.mkdir(parents=True, exist_ok=True)
    tmp = RECORD.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    tmp.replace(RECORD)


def darling() -> str:
    return shutil.which("darling") or ""


# ---------------------------------------------------------------- bundles
def extract_zip(archive: pathlib.Path, dest: pathlib.Path) -> None:
    """Unzip keeping what app bundles depend on: symlinks (frameworks are full
    of them) and executable bits."""
    root = dest.resolve()
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            name = info.filename
            if name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts or name.startswith("__MACOSX/"):
                continue
            target = dest / name
            mode = (info.external_attr >> 16) & 0xFFFF
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            # Nothing is written outside the folder, even through a symlink an
            # earlier entry planted.
            if not str(target.parent.resolve()).startswith(str(root) + os.sep) and target.parent.resolve() != root:
                raise RuntimeError("The download tries to write outside its folder, so it wasn't installed.")
            if stat.S_ISLNK(mode):
                link = z.read(info).decode("utf-8")
                if target.is_symlink() or target.exists():
                    target.unlink()
                os.symlink(link, target)
                continue
            with z.open(info) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
            if mode & 0o111:
                target.chmod(0o755)


def extract_dmg(image: pathlib.Path, dest: pathlib.Path) -> str:
    """A disk image, opened with 7-Zip (HFS+ and APFS). Its exit code isn't
    the verdict: nearly every Mac disk image carries an "Applications" link to
    /Applications, which 7-Zip refuses as dangerous and reports as an error
    although the app came out whole. Whether the app is there decides
    (install() looks); 7-Zip's output is returned for the log."""
    tool = shutil.which("7zz") or shutil.which("7z")
    if not tool:
        raise RuntimeError("Opening .dmg disk images needs 7-Zip. Install it with: sudo pacman -S 7zip")
    p = subprocess.run([tool, "x", "-y", f"-o{dest}", str(image)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return f"7-Zip exited {p.returncode}\n{p.stdout}"


def find_app(root: pathlib.Path, name: str) -> pathlib.Path | None:
    """The bundle called name, anywhere in what was unpacked (a disk image puts
    it under its volume name)."""
    want = pathlib.PurePosixPath(name).name
    for dirpath, dirnames, _ in os.walk(root):
        if want in dirnames:
            return pathlib.Path(dirpath) / want
        dirnames[:] = [d for d in dirnames if not d.endswith(".app")]
    return None


def info_plist(app: pathlib.Path) -> dict:
    try:
        with open(app / "Contents/Info.plist", "rb") as f:
            return plistlib.load(f)
    except (OSError, plistlib.InvalidFileException, ValueError):
        return {}


CPU_X86_64, CPU_ARM64 = 0x01000007, 0x0100000C


def architectures(binary: pathlib.Path) -> set[str]:
    """Which CPUs a Mach-O executable is built for (a universal binary has several)."""
    try:
        head = binary.read_bytes()[:4096]
    except OSError:
        return set()
    if len(head) < 8:
        return set()
    names = {CPU_X86_64: "x86_64", CPU_ARM64: "arm64"}
    magic = head[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):          # fat (universal), big-endian
        count = struct.unpack(">I", head[4:8])[0]
        size = 20 if magic == b"\xca\xfe\xba\xbe" else 32
        cpus = [struct.unpack(">i", head[8 + i * size:12 + i * size])[0] for i in range(min(count, 16))]
        return {names.get(c & 0xFFFFFFFF, "other") for c in cpus}
    if magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):          # thin, little-endian
        return {names.get(struct.unpack("<I", head[4:8])[0], "other")}
    return set()


def icon_png(app: pathlib.Path, plist: dict, out: pathlib.Path) -> bool:
    """The app's icon as a PNG: the largest PNG image inside its .icns (every
    icns since macOS 10.7 carries them)."""
    name = plist.get("CFBundleIconFile") or plist.get("CFBundleIconName") or ""
    candidates = []
    if name:
        candidates.append(app / "Contents/Resources" / (name if name.endswith(".icns") else name + ".icns"))
    candidates += sorted((app / "Contents/Resources").glob("*.icns"))
    for icns in candidates:
        try:
            data = icns.read_bytes()
        except OSError:
            continue
        if data[:4] != b"icns":
            continue
        best, pos = b"", 8
        while pos + 8 <= len(data):
            kind, length = data[pos:pos + 4], struct.unpack(">I", data[pos + 4:pos + 8])[0]
            if length < 8:
                break
            chunk = data[pos + 8:pos + length]
            if chunk[:8] == b"\x89PNG\r\n\x1a\n" and len(chunk) > len(best):
                best = chunk
            pos += length
        if best:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(best)
            return True
    return False


def desktop_file(token: str) -> pathlib.Path:
    return DATA / "applications" / f"gg-mac-{token}.desktop"


def write_launcher(token: str, name: str, desc: str, icon: str) -> None:
    f = desktop_file(token)
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text("\n".join([
        "[Desktop Entry]", "Type=Application", f"Name={name}",
        f"Comment={desc or 'Mac app'}", f"Exec=gg-mac-open {token}",
        f"Icon={icon or 'application-x-executable'}", "Categories=MacApp;",
        "X-GoldenGate-MacApp=true", f"X-GoldenGate-MacToken={token}", "",
    ]))


# ---------------------------------------------------------------- install
def install(token: str) -> int:
    """Download, verify, unpack and install; every step goes in a log
    (~/.cache/golden-gate/mac-logs/install-TOKEN.log), and a failure says why
    with the log's last lines, so it's never just "it failed"."""
    LOGS.mkdir(parents=True, exist_ok=True)
    log_path = LOGS / f"install-{token}.log"
    log: list[str] = [time.strftime("%Y-%m-%d %H:%M:%S") + f" installing {token}"]

    def fail(message: str) -> int:
        log.append("FAILED: " + message)
        log_path.write_text("\n".join(log) + "\n")
        tail = "\n".join(l for l in log[-8:] if l.strip())
        emit("error", id=token, message=message, details=tail + f"\n(full log: {log_path})", log=str(log_path))
        return 1

    try:
        return _install(token, log, fail)
    except Exception as exc:                       # never fail silently
        import traceback
        log.append(traceback.format_exc())
        return fail(f"Installing stopped unexpectedly ({type(exc).__name__}: {exc}).")
    finally:
        if log_path.parent.exists():
            log_path.write_text("\n".join(log) + "\n")


def _install(token: str, log: list[str], fail) -> int:
    try:
        cask = find(token)
    except RuntimeError as exc:
        return fail(str(exc))
    log.append(f"catalog: {cask['name']} {cask['version']} from {cask['url']} ({cask['kind']}, sha256 {cask['sha256'] or 'none'})")
    downloads = CACHE / "mac-downloads"
    emit("progress", id=token, progress=0.02, message=f"Downloading {cask['name']}…")
    last = [0.0]

    def progress(done: int, total: int) -> None:
        frac = done / total if total else 0
        if frac - last[0] >= 0.02 or done == total:
            last[0] = frac
            mb = done / 1e6
            emit("progress", id=token, progress=0.02 + 0.68 * frac,
                 message=f"Downloading {cask['name']}… {mb:.1f} MB" + (f" of {total / 1e6:.1f} MB" if total else ""))

    def download(c: dict) -> pathlib.Path | None:
        archive = downloads / f"{token}-{c['version'] or 'latest'}.{c['kind']}"
        try:
            fetch(c["url"], archive, progress)
        except OSError as exc:
            fail(f"The download didn't finish: {exc}.")
            return None
        log.append(f"downloaded {archive.stat().st_size} bytes")
        return archive

    def matches(archive: pathlib.Path, c: dict) -> bool:
        if not c["sha256"] or c["sha256"] == "no_check":
            log.append("no published checksum to check")
            return True
        h = hashlib.sha256()
        with open(archive, "rb") as f:
            for block in iter(lambda: f.read(1 << 20), b""):
                h.update(block)
        log.append(f"sha256 {h.hexdigest()} (expected {c['sha256']})")
        return h.hexdigest() == c["sha256"]

    archive = download(cask)
    if not archive:
        return 1
    emit("progress", id=token, progress=0.72, message="Verifying…")
    if not matches(archive, cask):
        # Usually the catalog was a day old and the developer has shipped a
        # new version since: refresh it and try once more.
        archive.unlink(missing_ok=True)
        log.append("checksum differs; refreshing the catalog and trying again")
        try:
            cask = next(c for c in load_catalog(refresh=True) if c["token"] == token)
        except (RuntimeError, StopIteration):
            return fail("The download doesn't match its published checksum, so it wasn't installed.")
        archive = download(cask)
        if not archive:
            return 1
        if not matches(archive, cask):
            archive.unlink(missing_ok=True)
            return fail("The download doesn't match its published checksum, so it wasn't installed.")

    emit("progress", id=token, progress=0.78, message="Opening the download…")
    with tempfile.TemporaryDirectory(prefix="gg-mac-") as tmp:
        root = pathlib.Path(tmp)
        try:
            if cask["kind"] == "dmg":
                log.append(extract_dmg(archive, root)[-3000:])
            else:
                extract_zip(archive, root)
        except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
            return fail(str(exc))
        app = find_app(root, cask["app"])
        if not app:
            found = sorted(str(p.relative_to(root)) for p in root.rglob("*.app"))[:10]
            log.append("apps in the download: " + (", ".join(found) or "none"))
            return fail(f"{cask['app']} wasn't in the download.")
        plist = info_plist(app)
        exe = app / "Contents/MacOS" / str(plist.get("CFBundleExecutable") or app.stem)
        arches = architectures(exe)
        log.append(f"{app.name}: executable {exe.name}, built for {', '.join(sorted(arches)) or 'unknown'}")
        if arches and "x86_64" not in arches:
            return fail(f"{cask['name']} is built only for Apple silicon; Darling runs Intel Mac apps, so it wasn't installed.")
        emit("progress", id=token, progress=0.9, message="Installing in Applications…")
        APPLICATIONS.mkdir(parents=True, exist_ok=True)
        target = APPLICATIONS / app.name
        if target.exists() or target.is_symlink():
            shutil.rmtree(target) if target.is_dir() and not target.is_symlink() else target.unlink()
        shutil.move(str(app), str(target))
    # The app's own programs must be executable, whatever the archive kept.
    for f in (target / "Contents/MacOS").glob("*"):
        if f.is_file() and not f.is_symlink():
            f.chmod(f.stat().st_mode | 0o755)

    plist = info_plist(target)
    icon = ICONS / f"{token}.png"
    has_icon = icon_png(target, plist, icon)
    write_launcher(token, cask["name"], cask["desc"], str(icon) if has_icon else "")
    data = records()
    data[token] = {
        "name": cask["name"], "version": str(plist.get("CFBundleShortVersionString") or cask["version"]),
        "catalogVersion": cask["version"], "path": str(target), "bundleId": plist.get("CFBundleIdentifier", ""),
        "executable": str(plist.get("CFBundleExecutable") or target.stem),
        "arch": sorted(arches), "icon": str(icon) if has_icon else "", "installed": int(time.time()),
        "opened": None,
    }
    save_records(data)
    archive.unlink(missing_ok=True)
    log.append(f"installed in {target}")
    emit("done", id=token, progress=1.0, path=str(target), arch=sorted(arches))
    return 0


def remove(token: str) -> int:
    data = records()
    rec = data.pop(token, None)
    if rec:
        path = pathlib.Path(rec["path"])
        if path.is_dir() and path.suffix == ".app" and path.parent == APPLICATIONS:
            shutil.rmtree(path, ignore_errors=True)
    desktop_file(token).unlink(missing_ok=True)
    (ICONS / f"{token}.png").unlink(missing_ok=True)
    save_records(data)
    emit("done", id=token)
    return 0


# ---------------------------------------------------------------- open
def open_app(token: str, wait: float = 6.0) -> int:
    """Open with Darling. A Darling program that ends within a few seconds with
    an error didn't open: say so, with Darling's last words, and remember it."""
    data = records()
    rec = data.get(token)
    if not rec:
        emit("error", id=token, message="That app isn't installed.")
        return 1
    if not darling():
        emit("error", id=token, code="no-darling",
             message="Mac app support isn't set up yet. Set it up in the App Store's Mac Apps section.")
        return 1
    exe = pathlib.Path(rec["path"]) / "Contents/MacOS" / rec["executable"]
    # Darling sees the Linux file system under /Volumes/SystemRoot.
    inside = "/Volumes/SystemRoot" + str(exe)
    LOGS.mkdir(parents=True, exist_ok=True)
    log = LOGS / f"{token}.log"
    with open(log, "w") as out:
        proc = subprocess.Popen([darling(), inside], stdout=out, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + wait
    while time.time() < deadline and proc.poll() is None:
        time.sleep(0.2)
    code = proc.poll()
    if code is not None and code != 0:
        tail = [l for l in log.read_text(errors="replace").splitlines() if l.strip()][-6:]
        rec["opened"] = False
        rec["lastError"] = "\n".join(tail)
        save_records(data)
        emit("error", id=token, code="didnt-open",
             message=f"{rec['name']} didn't open under Darling (exit {code}). Many Mac apps don't run yet.",
             details=rec["lastError"])
        return 1
    rec["opened"] = True
    rec.pop("lastError", None)
    save_records(data)
    emit("done", id=token)
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "catalog":
            apps = load_catalog(refresh="--refresh" in args)
            emit("mac-catalog", apps=apps, featured=FEATURED)
            return 0
        if cmd == "all":                  # what the App Store needs, in one go
            try:
                apps, error = load_catalog(refresh="--refresh" in args), ""
            except RuntimeError as exc:
                apps, error = [], str(exc)
            emit("mac-all", apps=apps, featured=FEATURED, installed=records(), darling=bool(darling()), error=error)
            return 0
        if cmd == "installed":
            emit("mac-installed", apps=records())
            return 0
        if cmd == "status":
            emit("mac-status", darling=bool(darling()), path=darling())
            return 0
        if cmd == "install" and len(args) == 1:
            return install(args[0])
        if cmd == "remove" and len(args) == 1:
            return remove(args[0])
        if cmd == "open" and len(args) == 1:
            return open_app(args[0])
    except RuntimeError as exc:
        emit("error", message=str(exc))
        return 1
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
