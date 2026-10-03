"""Golden Gate updates from GitHub, for Software Update.

Golden Gate itself (the shell, the apps, the themes) comes from its GitHub
repository rather than from Arch packages. This module asks GitHub for the
newest commit on the branch the system was built from, says what changed
since the installed one, and installs it:

  1. download that exact commit's snapshot (GitHub's tarball of the commit)
  2. install any packages the new package list adds (official repos only)
  3. run its scripts/install.sh --system / , with the previous runtime kept
     aside and put back if the install fails
  4. bring every account's own copies up to date: the shell (always: it is
     Golden Gate's, not the user's) and the Hyprland, GTK, Ghostty and font
     files, but only those the user hasn't changed; an edited file is left
     alone and the new one is written next to it as NAME.golden-gate-new
  5. the installed-system parts of the ISO overlay (polkit, user services),
     the HyprGlass plugin the build pins, and the services the build enables
  6. record the new version in /usr/share/golden-gate/version.json

Where updates come from: /etc/golden-gate/update.json {"repo", "branch"},
else the repository and branch recorded at build time, else Golden Gate's
development branch of MobiLaunch/GoldenApple. A private repository needs a read-only
access token in /etc/golden-gate/update-token (root:wheel 0640), set from
Settings ▸ Software Update ▸ Update Source.

GG_UPDATE_API and GG_UPDATE_ROOT point the module at a stand-in GitHub and a
staging root (tests).

A system installed before Software Update knew about Golden Gate is brought
up to date once from a checkout of the repository:

    sudo python3 apps/settings/golden_update.py install-local
"""
from __future__ import annotations

import filecmp
import hashlib
import json
import os
import pwd
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

API = os.environ.get("GG_UPDATE_API", "https://api.github.com").rstrip("/")
ROOT = Path(os.environ.get("GG_UPDATE_ROOT", "/"))
DEFAULT_REPO = "MobiLaunch/GoldenApple"
# Development happens here; main gets it when the work is merged.
DEFAULT_BRANCH = "claude/linux-macos-golden-gate-ui-pckc7s"
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
BRANCH_RE = re.compile(r"^(?!.*\.\.)[A-Za-z0-9_./-]{1,200}$")

# Files every account gets from /etc/skel/.config that Golden Gate keeps current.
MANAGED = [
    "hypr/hyprland.conf", "hypr/hypridle.conf", "hypr/golden-gate/motion.conf",
    "hypr/golden-gate/report-config-errors.sh", "hypr/golden-gate/machine-conf.sh",
    "gtk-4.0/gtk.css", "gtk-3.0/gtk.css", "fontconfig/conf.d/60-golden-gate.conf",
    "ghostty/config",
]
# Live-session-only parts of the ISO overlay that an installed system must not get.
LIVE_ONLY = (
    "etc/sudoers.d/10-golden-live",
    "etc/systemd/system/getty@tty1.service.d",
    "etc/systemd/system/gg-live-home.service",
)


def path(p: str) -> Path:
    return ROOT / p.lstrip("/")


# ------------------------------------------------------------------ settings
def installed() -> dict:
    try:
        data = json.loads(path("/usr/share/golden-gate/version.json").read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def source() -> dict:
    """Where updates come from, and the token if this account may read it."""
    cfg = {}
    try:
        cfg = json.loads(path("/etc/golden-gate/update.json").read_text())
    except (OSError, ValueError):
        pass
    built = installed()
    repo = cfg.get("repo") or built.get("repo") or DEFAULT_REPO
    branch = cfg.get("branch") or built.get("branch") or DEFAULT_BRANCH
    token = ""
    try:
        token = path("/etc/golden-gate/update-token").read_text().strip()
    except OSError:
        pass
    return {"repo": repo if REPO_RE.match(repo) else DEFAULT_REPO,
            "branch": branch if BRANCH_RE.match(branch) else DEFAULT_BRANCH,
            "token": token}


def set_source(repo: str, branch: str, token: str | None) -> None:
    """As root: save the repository, branch and (when given) token."""
    if not REPO_RE.match(repo):
        raise ValueError("The repository should look like owner/name.")
    if not BRANCH_RE.match(branch):
        raise ValueError("That isn't a valid branch name.")
    folder = path("/etc/golden-gate")
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "update.json").write_text(json.dumps({"repo": repo, "branch": branch}, indent=2) + "\n")
    if token is not None:
        tok = folder / "update-token"
        if token:
            tok.write_text(token.strip() + "\n")
            os.chmod(tok, 0o640)
            try:
                os.chown(tok, 0, _gid("wheel"))
            except (OSError, KeyError):
                pass
        else:
            tok.unlink(missing_ok=True)


def _gid(group: str) -> int:
    import grp
    return grp.getgrnam(group).gr_gid


# ------------------------------------------------------------------ GitHub
class GitHubError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


def _request(url: str, token: str, accept: str = "application/vnd.github+json", timeout: int = 20):
    headers = {"Accept": accept, "User-Agent": "golden-gate-update", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=timeout)


def api(endpoint: str, token: str) -> dict:
    try:
        with _request(API + endpoint, token) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise GitHubError(e.code, e.reason or "")
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise GitHubError(0, str(getattr(e, "reason", e)))


def check() -> dict:
    """What Software Update shows for Golden Gate."""
    src = source()
    now = installed()
    out = {"repo": src["repo"], "branch": src["branch"], "current": now.get("commit", ""),
           "currentDate": now.get("date", ""), "available": False, "notes": [], "ahead": 0,
           "needsToken": False, "error": ""}
    try:
        head = api(f"/repos/{src['repo']}/commits/{src['branch']}", src["token"])
    except GitHubError as e:
        if e.status in (401, 403, 404):
            out["needsToken"] = not src["token"] or e.status == 401
            out["error"] = ("Golden Gate's repository is private or the branch is missing. "
                            "Add an access token in Update Source." if out["needsToken"]
                            else f"GitHub refused the request ({e.status}).")
        else:
            out["error"] = "Couldn't reach GitHub to check for Golden Gate updates."
        return out
    latest = head.get("sha", "")
    commit = head.get("commit") or {}
    out.update(latest=latest, latestDate=(commit.get("committer") or {}).get("date", ""),
               latestSubject=str(commit.get("message", "")).split("\n")[0][:200])
    if not latest or latest == out["current"]:
        return out
    out["available"] = True
    if out["current"]:
        try:
            cmp = api(f"/repos/{src['repo']}/compare/{out['current']}...{latest}", src["token"])
            out["ahead"] = int(cmp.get("ahead_by") or 0)
            out["notes"] = [str((c.get("commit") or {}).get("message", "")).split("\n")[0][:200]
                            for c in reversed(cmp.get("commits") or [])][:20]
        except GitHubError:
            pass
    if not out["notes"]:
        out["notes"] = [out["latestSubject"]] if out.get("latestSubject") else []
    return out


# ------------------------------------------------------------------ install
Emit = Callable[..., None]


def _run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, text=True, capture_output=True, **kw)


def download(src: dict, sha: str, into: Path) -> Path:
    """The commit's snapshot, unpacked safely; returns its top folder."""
    archive = into / "golden-gate.tar.gz"
    try:
        with _request(f"{API}/repos/{src['repo']}/tarball/{sha}", src["token"],
                      accept="application/vnd.github+json", timeout=120) as r, open(archive, "wb") as f:
            shutil.copyfileobj(r, f)
    except urllib.error.HTTPError as e:
        raise GitHubError(e.code, f"Couldn't download the update ({e.code}).")
    except (urllib.error.URLError, OSError) as e:
        raise GitHubError(0, f"Couldn't download the update: {getattr(e, 'reason', e)}")
    dest = into / "src"
    dest.mkdir()
    with tarfile.open(archive) as tar:
        members = []
        for m in tar.getmembers():
            name = Path(m.name)
            if name.is_absolute() or ".." in name.parts or m.isdev():
                raise GitHubError(0, "The update archive is malformed.")
            members.append(m)
        try:
            tar.extractall(dest, members=members, filter="data")
        except TypeError:                                   # Python < 3.12
            tar.extractall(dest, members=members)
    tops = [p for p in dest.iterdir() if p.is_dir()]
    if len(tops) != 1 or not (tops[0] / "scripts/install.sh").exists():
        raise GitHubError(0, "The update doesn't contain Golden Gate.")
    return tops[0]


def _package_list(tree: Path) -> list[str]:
    names = []
    for name in ("distro/archiso/packages.x86_64", "distro/archiso/packages.extra"):
        try:
            for line in (tree / name).read_text().splitlines():
                line = line.split("#", 1)[0].strip()
                if line:
                    names.append(line)
        except OSError:
            pass
    return names


def install_packages(tree: Path, emit: Emit) -> list[str]:
    """New packages from the list that the official repos have; returns the
    ones that must be built from the AUR and so were left out."""
    if not shutil.which("pacman") or ROOT != Path("/"):
        return []
    wanted = _package_list(tree)
    missing = [p for p in _run(["pacman", "-T", *wanted]).stdout.split() if p]
    if not missing:
        return []
    available = [p for p in missing if _run(["pacman", "-Si", p]).returncode == 0]
    skipped = [p for p in missing if p not in available]
    if available:
        emit("progress", progress=0.9, message="Installing " + ", ".join(available[:4]) + ("…" if len(available) > 4 else ""), remaining=-1)
        proc = _run(["pacman", "-S", "--needed", "--noconfirm", "--noprogressbar", *available], timeout=3600)
        if proc.returncode != 0:
            skipped += available
    return skipped


def _snapshot_skel(into: Path) -> Path:
    keep = into / "old-skel"
    skel = path("/etc/skel/.config")
    for rel in MANAGED + [f"ghostty/themes/{p.name}" for p in (skel / "ghostty/themes").glob("*")]:
        f = skel / rel
        if f.is_file():
            (keep / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, keep / rel)
    return keep


def _accounts():
    for entry in pwd.getpwall():
        if not (1000 <= entry.pw_uid < 60000) or entry.pw_shell.endswith(("nologin", "false")):
            continue
        home = path(entry.pw_dir) if ROOT != Path("/") else Path(entry.pw_dir)
        if (home / ".config/quickshell/golden-gate").is_dir():
            yield entry, home


def _chown_tree(p: Path, uid: int, gid: int):
    if os.geteuid() != 0:
        return
    for dirpath, dirnames, filenames in os.walk(p):
        for name in [dirpath, *[os.path.join(dirpath, n) for n in dirnames + filenames]]:
            try:
                os.lchown(name, uid, gid)
            except OSError:
                pass


def refresh_accounts(old_skel: Path) -> list[str]:
    """Bring each account's copies up to date. Returns files left alone."""
    skel = path("/etc/skel/.config")
    kept = []
    themes = [f"ghostty/themes/{p.name}" for p in (skel / "ghostty/themes").glob("*")]
    for entry, home in _accounts():
        conf = home / ".config"
        shell = conf / "quickshell/golden-gate"
        fresh = skel / "quickshell/golden-gate"
        if fresh.is_dir():
            tmp = shell.with_name("golden-gate.updating")
            shutil.rmtree(tmp, ignore_errors=True)
            shutil.copytree(fresh, tmp, symlinks=True)
            shutil.rmtree(shell, ignore_errors=True)
            tmp.rename(shell)
            _chown_tree(shell, entry.pw_uid, entry.pw_gid)
        for rel in MANAGED + themes:
            new, old, mine = skel / rel, old_skel / rel, conf / rel
            if not new.is_file():
                continue
            if mine.exists() and filecmp.cmp(mine, new, shallow=False):
                continue
            if not mine.exists() or (old.is_file() and filecmp.cmp(mine, old, shallow=False)):
                mine.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(new, mine)
                target = mine
            else:
                target = mine.with_name(mine.name + ".golden-gate-new")
                shutil.copy2(new, target)
                kept.append(f"~{entry.pw_name}/.config/{rel}")
            if os.geteuid() == 0:
                os.lchown(target, entry.pw_uid, entry.pw_gid)
    return kept


def apply_overlay(tree: Path):
    overlay = tree / "distro/archiso/overlay"
    for f in sorted(overlay.rglob("*")):
        rel = f.relative_to(overlay).as_posix()
        if f.is_dir() or rel.startswith(LIVE_ONLY):
            continue
        dest = path("/" + rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dest)


def update_hyprglass(tree: Path):
    text = (tree / "distro/archiso/build.sh").read_text()
    ver = re.search(r'^HYPRGLASS_VERSION="?([^"\s]+)"?', text, re.M)
    sha = re.search(r'^HYPRGLASS_SHA256="?([0-9a-f]{64})"?', text, re.M)
    plugin = path("/usr/lib/golden-gate/hyprglass.so")
    if not (ver and sha) or not plugin.parent.is_dir():
        return
    if plugin.exists() and hashlib.sha256(plugin.read_bytes()).hexdigest() == sha.group(1):
        return
    url = f"https://github.com/hyprnux/hyprglass/releases/download/{ver.group(1)}/hyprglass.so"
    with urllib.request.urlopen(url, timeout=60) as r:
        data = r.read()
    if hashlib.sha256(data).hexdigest() != sha.group(1):
        raise GitHubError(0, "The HyprGlass download didn't match its checksum.")
    tmp = plugin.with_suffix(".new")
    tmp.write_bytes(data)
    os.chmod(tmp, 0o755)
    tmp.replace(plugin)


def enable_services(tree: Path):
    if ROOT != Path("/") or not shutil.which("systemctl"):
        return
    text = (tree / "distro/archiso/build.sh").read_text()
    for unit in sorted(set(re.findall(r'/usr/lib/systemd/system/([\w@.-]+\.service) "\$WANTS/', text))):
        if unit.startswith("gg-live") or not Path("/usr/lib/systemd/system", unit).exists():
            continue
        if _run(["systemctl", "is-enabled", unit]).stdout.strip() != "enabled":
            _run(["systemctl", "enable", "--now", unit], timeout=60)


def apply(emit: Emit) -> bool:
    """As root: install the newest Golden Gate. False when nothing was done."""
    status = check()
    if not status["available"]:
        if status["error"]:
            emit("notice", message=status["error"])
        return False
    src = source()
    work = Path(tempfile.mkdtemp(prefix="gg-golden-update-", dir=path("/var/tmp") if path("/var/tmp").is_dir() else None))
    try:
        emit("progress", progress=0.86, message="Downloading Golden Gate…", remaining=-1)
        tree = download(src, status["latest"], work)
        version = {"repo": src["repo"], "branch": src["branch"], "commit": status["latest"],
                   "date": status.get("latestDate", ""), "subject": status.get("latestSubject", "")}
        return install_tree(tree, version, emit, work)
    except GitHubError as e:
        emit("error", message=str(e))
        return False


def install_local() -> int:
    """As root, from a checkout of the repository: install it as an update."""
    if os.geteuid() != 0 and ROOT == Path("/"):
        print("Run this with sudo: it installs Golden Gate for the whole system.")
        return 77
    tree = Path(__file__).resolve().parents[2]
    git = lambda *a: _run(["git", "-C", str(tree), *a]).stdout.strip()
    origin = git("remote", "get-url", "origin")
    m = re.match(r"^(?:https://|git@)github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", origin)
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    version = {"repo": m.group(1) if m else DEFAULT_REPO,
               "branch": branch if branch and branch != "HEAD" else DEFAULT_BRANCH,
               "commit": git("rev-parse", "HEAD"), "date": git("log", "-1", "--format=%cI"),
               "subject": git("log", "-1", "--format=%s")}

    def say(event, **kw):
        if kw.get("message"):
            print(("! " if event in ("error", "notice") else "› ") + kw["message"], flush=True)

    work = Path(tempfile.mkdtemp(prefix="gg-golden-update-"))
    try:
        ok = install_tree(tree, version, say, work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if ok:
        print(f"› Golden Gate {version['commit'][:7]} installed from {version['repo']} ({version['branch']}).")
        print("› Settings ▸ Software Update will find later updates on GitHub. Log out and back in to finish.")
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["install-local"]:
        raise SystemExit(install_local())
    print(__doc__)


def install_tree(tree: Path, version: dict, emit: Emit, work: Path) -> bool:
    """Install Golden Gate from an unpacked tree (see apply's steps)."""
    backup = work / "previous"
    runtime = path("/usr/share/golden-gate")
    skel_shell = path("/etc/skel/.config/quickshell/golden-gate")
    try:
        skipped = install_packages(tree, emit)
        emit("progress", progress=0.92, message="Installing Golden Gate…", remaining=-1)
        old_skel = _snapshot_skel(work)
        for p, name in ((runtime, "runtime"), (skel_shell, "skel-shell")):
            if p.exists():
                shutil.copytree(p, backup / name, symlinks=True)
        proc = _run(["bash", str(tree / "scripts/install.sh"), "--system", str(ROOT)],
                    env={**os.environ, "GG_SKIP_BUILD": "1"}, timeout=1800, cwd=str(tree))
        if proc.returncode != 0:
            for p, name in ((runtime, "runtime"), (skel_shell, "skel-shell")):
                if (backup / name).exists():
                    shutil.rmtree(p, ignore_errors=True)
                    shutil.copytree(backup / name, p, symlinks=True)
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-1:] or ["unknown error"]
            emit("error", message="Golden Gate's update didn't install, and the previous version was kept: " + tail[0][:200])
            return False
        emit("progress", progress=0.96, message="Updating your settings…", remaining=-1)
        kept = refresh_accounts(old_skel)
        apply_overlay(tree)
        try:
            update_hyprglass(tree)
        except (OSError, GitHubError, urllib.error.URLError):
            pass                                # the old plugin keeps working
        enable_services(tree)
        (runtime / "version.json").write_text(json.dumps({
            **version, "date": version.get("date") or datetime.now(timezone.utc).isoformat(),
            "installed": datetime.now(timezone.utc).isoformat(),
        }, indent=2) + "\n")
        if kept:
            emit("notice", message="Kept your edited " + ", ".join(kept[:3]) + ("…" if len(kept) > 3 else "")
                 + "; the new versions are beside them as .golden-gate-new.")
        if skipped:
            emit("notice", message="Not installed (needs the AUR): " + ", ".join(skipped[:6]))
        return True
    except GitHubError as e:
        emit("error", message=str(e))
        return False
    finally:
        shutil.rmtree(work, ignore_errors=True)
