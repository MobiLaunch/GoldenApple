"""CitronOS updates from GitHub, for Software Update.

CitronOS itself (the shell, the apps, the themes) comes from its GitHub
repository rather than from Arch packages. This module asks GitHub for the
newest commit on the branch the system was built from, says what changed
since the installed one, and installs it:

  1. download that exact commit's snapshot (GitHub's tarball of the commit)
  2. install any packages the new package list adds (official repos only)
  3. run its scripts/install.sh --system / , with the previous runtime kept
     aside and put back if the install fails
  4. bring every account's own copies up to date: the shell (always: it is
     CitronOS's, not the user's) and the Hyprland, GTK, Ghostty and font
     files, but only those the user hasn't changed; an edited file is left
     alone and the new one is written next to it as NAME.golden-gate-new
  5. the installed-system parts of the ISO overlay (polkit, user services),
     the HyprGlass plugin the build pins, and the services the build enables
  6. record the new version in /usr/share/golden-gate/version.json

Where updates come from: /etc/golden-gate/update.json {"repo", "branch"},
else the repository and branch recorded at build time, else CitronOS's
development branch of MobiLaunch/GoldenApple. A private repository needs a read-only
access token in /etc/golden-gate/update-token (root:wheel 0640), set from
Settings ▸ Software Update ▸ Update Source.

GG_UPDATE_API and GG_UPDATE_ROOT point the module at a stand-in GitHub and a
staging root (tests).

Without GitHub, from a USB stick:

  on the installed system, from an update bundle made with
  scripts/make-update-bundle.sh (or a checkout of the repository):
      tar xzf golden-gate-update.tar.gz
      sudo python3 golden-gate/apps/settings/golden_update.py install-local

  from the live ISO, onto the CitronOS installed on this computer's disk
  (the ISO carries its own source as /usr/share/golden-gate/source.tar.gz):
      sudo gg-update-disk

    install-local [--from TREE|BUNDLE.tar.gz] [--root MOUNTED-SYSTEM]
    update-disk   find the installed system, confirm, and install-local onto it
"""
from __future__ import annotations

import filecmp
import hashlib
import json
import os
import pwd
import re
import shutil
import stat
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

# Files every account gets from /etc/skel/.config that CitronOS keeps current.
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

# What the live ISO (archiso's releng profile plus CitronOS's overlay) leaves
# on a system the installer copies from it, and an installed system must not
# keep. archiso.conf matters most: mkinitcpio reads conf.d after
# mkinitcpio.conf, so it swapped the installed boot image's hooks for the live
# ISO's, which wait for the USB stick's volume and stop when it isn't there.
LIVE_LEFTOVERS = (
    "etc/mkinitcpio.conf.d/archiso.conf",
    "etc/sudoers.d/10-golden-live",
    "etc/systemd/system/getty@tty1.service.d",
    "etc/systemd/system/gg-live-home.service",
    "etc/systemd/system/multi-user.target.wants/gg-live-home.service",
    "etc/systemd/system/cloud-init.target.wants",              # waits for cloud datasources
    "etc/systemd/system/sysinit.target.wants/systemd-time-wait-sync.service",
    "etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service",
    "etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf",
    "etc/systemd/system/etc-pacman.d-gnupg.mount",            # the keyring on a tmpfs
    "etc/systemd/system/pacman-init.service",
    "etc/systemd/system/multi-user.target.wants/pacman-init.service",
    "etc/systemd/system/choose-mirror.service",
    "etc/systemd/system/multi-user.target.wants/choose-mirror.service",
    "etc/systemd/system/livecd-talk.service",
    "etc/systemd/system/multi-user.target.wants/livecd-talk.service",
    "etc/systemd/system/livecd-alsa-unmuter.service",
    "etc/systemd/system/sound.target.wants/livecd-alsa-unmuter.service",
    "etc/systemd/system/multi-user.target.wants/sshd.service",   # with root login allowed
    "etc/ssh/sshd_config.d/10-archiso.conf",
    "etc/systemd/journald.conf.d/volatile-storage.conf",      # logs that vanish at reboot
    "etc/systemd/logind.conf.d/do-not-suspend.conf",
    "etc/pacman.d/hooks/zzzz99-remove-custom-hooks-from-airootfs.hook",
    "etc/pacman.d/hooks/uncomment-mirrors.hook",
    "etc/motd",
    "usr/local/bin/choose-mirror",
    "usr/local/bin/Installation_guide",
    "usr/local/bin/livecd-sound",
    "usr/local/share/livecd-sound",
)


def ensure_keyring(root: Path) -> None:
    """The live ISO kept pacman's keyring on a tmpfs, rebuilt every boot; an
    installed system keeps one on disk. Create it if the copy didn't bring one."""
    gnupg = root / "etc/pacman.d/gnupg"
    if any((gnupg / f).exists() for f in ("pubring.kbx", "pubring.gpg")) or not shutil.which("pacman-key"):
        return
    pre = [] if root == Path("/") else ["arch-chroot", str(root)]
    _run([*pre, "pacman-key", "--init"], timeout=300)
    _run([*pre, "pacman-key", "--populate"], timeout=300)


def remove_live_leftovers(root: Path) -> bool:
    """Remove the live ISO's leftovers from an installed system at `root`.
    True when the boot image must be rebuilt (archiso's hooks were in it)."""
    rebuild = (root / "etc/mkinitcpio.conf.d/archiso.conf").exists()
    for rel in LIVE_LEFTOVERS:
        p = root / rel
        if p.is_dir() and not p.is_symlink():
            shutil.rmtree(p, ignore_errors=True)
        elif p.exists() or p.is_symlink():
            p.unlink()
    return rebuild


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
    if token is not None:
        token = clean_token(token)
    folder = path("/etc/golden-gate")
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "update.json").write_text(json.dumps({"repo": repo, "branch": branch}, indent=2) + "\n")
    if token is not None:
        tok = folder / "update-token"
        if token:
            tok.write_text(token + "\n")
            os.chmod(tok, 0o640)
            try:
                os.chown(tok, 0, _gid("wheel"))
            except (OSError, KeyError):
                pass
        else:
            tok.unlink(missing_ok=True)


def clean_token(token: str) -> str:
    """A token as pasted, without what copying tends to add: spaces, line
    breaks, quotes or a "Bearer " in front. GitHub tokens are letters, digits
    and underscores only."""
    t = "".join(token.split()).strip("\"'`")
    for prefix in ("Bearer", "bearer", "token", "Token"):
        if t.startswith(prefix) and len(t) > len(prefix) + 20:
            t = t[len(prefix):].lstrip(":=")
    if t and not re.fullmatch(r"[A-Za-z0-9_]{20,255}", t):
        raise ValueError("That doesn't look like a GitHub access token. Copy it again from GitHub "
                         "(it starts with github_pat_ or ghp_).")
    return t


def _gid(group: str) -> int:
    import grp
    return grp.getgrnam(group).gr_gid


# ------------------------------------------------------------------ GitHub
class GitHubError(Exception):
    def __init__(self, status: int, message: str, rate_limited: bool = False):
        super().__init__(message)
        self.status = status
        self.rate_limited = rate_limited


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
        raise GitHubError(e.code, e.reason or "", e.code in (403, 429)
                          and (e.headers.get("X-RateLimit-Remaining") == "0" or e.code == 429))
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise GitHubError(0, str(getattr(e, "reason", e)))


TOKEN_HELP = ("For a fine-grained token, set Repository access to Only select repositories → {name}, "
              "and Permissions → Contents to Read-only. A classic token needs the repo scope.")


def refusal(e: GitHubError, src: dict) -> tuple[str, bool]:
    """Why GitHub said no, in words that say what to change, and whether the
    fix is a (different) access token."""
    repo, branch, token = src["repo"], src["branch"], src["token"]
    help_ = TOKEN_HELP.format(name=repo.split("/")[-1])
    if e.status == 0:
        return "Couldn't reach GitHub to check for CitronOS updates.", False
    if e.rate_limited:
        return "GitHub's limit on checks was reached for now. Try again in an hour" + \
            ("." if token else ", or add an access token in Update Source."), False
    if e.status == 401:
        return "GitHub didn't accept the access token: it may be mistyped, expired or revoked. " \
               "Make a new one and save it in Update Source.", True
    if e.status == 403:
        return f"The access token isn't allowed to read {repo}. " + help_, True
    if e.status == 404:
        if not token:
            return f"{repo} is private (or doesn't exist). Add an access token in Update Source.", True
        try:
            api(f"/repos/{repo}", token)
        except GitHubError:
            return f"The access token can't see {repo}. " + help_, True
        return f"{repo} has no branch named \u201c{branch}\u201d. Check the branch in Update Source.", False
    return f"GitHub refused the request ({e.status}).", False


def verify_source(repo: str, branch: str, token: str) -> tuple[str, bool] | None:
    """None when GitHub serves `branch` of `repo` with this token; otherwise
    refusal()'s reason, and whether the token is what has to change."""
    if not REPO_RE.match(repo) or not BRANCH_RE.match(branch):
        return None                     # set_source says what's wrong with them
    try:
        api(f"/repos/{repo}/commits/{branch}", token)
    except GitHubError as e:
        message, token_problem = refusal(e, {"repo": repo, "branch": branch, "token": token})
        missing_branch = e.status == 404 and "no branch named" in message
        return message, token_problem or missing_branch
    return None


def check() -> dict:
    """What Software Update shows for CitronOS."""
    src = source()
    now = installed()
    out = {"repo": src["repo"], "branch": src["branch"], "current": now.get("commit", ""),
           "currentDate": now.get("date", ""), "available": False, "notes": [], "ahead": 0,
           "needsToken": False, "error": ""}
    token_file = path("/etc/golden-gate/update-token")
    if not src["token"] and token_file.exists():
        out["error"] = ("A token is saved, but this account can't read it. "
                        "Only administrators can check for CitronOS updates.")
        return out
    try:
        head = api(f"/repos/{src['repo']}/commits/{src['branch']}", src["token"])
    except GitHubError as e:
        out["error"], out["needsToken"] = refusal(e, src)
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
    return unpack(archive, into / "src")


def unpack(archive: Path, dest: Path) -> Path:
    """A snapshot or bundle, unpacked safely; returns its one top folder."""
    dest.mkdir(parents=True, exist_ok=True)
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
        raise GitHubError(0, "The update doesn't contain CitronOS.")
    return tops[0]


class UpdateFailed(Exception):
    """A step of installing CitronOS failed; the message says which and why."""


def _package_list(tree: Path, name: str) -> list[str]:
    names = []
    try:
        for line in (tree / name).read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                names.append(line)
    except OSError:
        pass
    return names


def _pacman_reason(proc: subprocess.CompletedProcess) -> str:
    lines = [l for l in (proc.stdout + proc.stderr).strip().splitlines() if l.strip()]
    errors = [l for l in lines if l.lower().startswith("error")]
    return ((errors or lines or ["pacman exited with status %d" % proc.returncode])[-1])[:200]


def install_packages(tree: Path, emit: Emit) -> dict[str, str]:
    """The packages this CitronOS needs that aren't installed yet. Required
    ones (packages.x86_64, from the official repositories) must install, or
    the update stops here with nothing changed (UpdateFailed). Optional ones
    (packages.extra: may need the AUR) are tried; returns those left out,
    with why."""
    if not shutil.which("pacman") or not path("/var/lib/pacman/local").is_dir():
        return {}
    pacman = ["pacman"] if ROOT == Path("/") else ["pacman", "--sysroot", str(ROOT)]
    required = _package_list(tree, "distro/archiso/packages.x86_64")
    optional = [p for p in _package_list(tree, "distro/archiso/packages.extra") if p not in required]
    missing = set(_run([*pacman, "-T", *required, *optional]).stdout.split()) if required or optional else set()
    need = [p for p in required if p in missing]
    want = [p for p in optional if p in missing]
    if need:
        unavailable = [p for p in need if _run([*pacman, "-Si", p]).returncode != 0]
        if unavailable:
            raise UpdateFailed("This version needs packages the package repositories don't have right now: "
                               + ", ".join(unavailable[:6]) + ". Nothing was changed; try again later.")
        emit("progress", progress=0.88, message="Installing " + ", ".join(need[:4]) + ("…" if len(need) > 4 else ""), remaining=-1)
        proc = _run([*pacman, "-S", "--needed", "--noconfirm", "--noprogressbar", *need], timeout=3600)
        if proc.returncode != 0:
            raise UpdateFailed("Packages this version needs couldn't be installed, so nothing was changed: " + _pacman_reason(proc))
    left: dict[str, str] = {}
    for p in want:
        if _run([*pacman, "-Si", p]).returncode != 0:
            left[p] = "needs the AUR"
            continue
        proc = _run([*pacman, "-S", "--needed", "--noconfirm", "--noprogressbar", p], timeout=1800)
        if proc.returncode != 0:
            left[p] = _pacman_reason(proc)
    return left


def _snapshot_skel(into: Path) -> Path:
    keep = into / "old-skel"
    skel = path("/etc/skel/.config")
    for rel in MANAGED + [f"ghostty/themes/{p.name}" for p in (skel / "ghostty/themes").glob("*")]:
        f = skel / rel
        if f.is_file():
            (keep / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, keep / rel)
    return keep


def _target_passwd():
    """The accounts of the system being updated: this one, or the one mounted
    at ROOT (a disk updated from the live ISO has its own users)."""
    if ROOT == Path("/") or not path("/etc/passwd").exists():
        return pwd.getpwall()
    rows = []
    for line in path("/etc/passwd").read_text().splitlines():
        f = line.split(":")
        if len(f) == 7 and f[2].isdigit() and f[3].isdigit():
            rows.append(pwd.struct_passwd((f[0], f[1], int(f[2]), int(f[3]), f[4], f[5], f[6])))
    return rows


def _accounts():
    for entry in _target_passwd():
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
    """The system files CitronOS ships (kept beforehand by install_tree)."""
    overlay = tree / "distro/archiso/overlay"
    for f in sorted(overlay.rglob("*")):
        rel = f.relative_to(overlay).as_posix()
        if f.is_dir() or rel.startswith(LIVE_ONLY):
            continue
        dest = path("/" + rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dest)


def update_hyprglass(tree: Path, emit: Emit | None = None) -> None:
    """The Liquid Glass plugin this version pins, for the Hyprland it was
    built for (HYPRGLASS_HYPRLAND in build.sh, stamped beside the plugin).
    A plugin is never kept or installed for a Hyprland other than its own:
    then it's marked incompatible (gg-hyprglass-sync won't load it, and uses
    Hyprland's own blur instead) and a notice says so, even when the bytes
    on disk already match."""
    emit = emit or (lambda *a, **k: None)
    text = (tree / "distro/archiso/build.sh").read_text()
    ver = re.search(r'^HYPRGLASS_VERSION="?([^"\s]+)"?', text, re.M)
    sha = re.search(r'^HYPRGLASS_SHA256="?([0-9a-f]{64})"?', text, re.M)
    target = re.search(r'^HYPRGLASS_HYPRLAND="?([^"\s]+)"?', text, re.M)
    plugin = path("/usr/lib/golden-gate/hyprglass.so")
    if not (ver and sha) or not plugin.parent.is_dir():
        return
    stamp = plugin.with_name(plugin.name + ".hyprland")
    off = plugin.with_name(plugin.name + ".incompatible")
    built_for = target.group(1) if target else ""
    installed = hyprland_release()
    if built_for and installed and installed != built_for:
        off.write_text(f"built for Hyprland {built_for}; installed {installed}\n")
        emit("notice", message=f"Liquid Glass is off for now: its plugin is built for Hyprland {built_for}, "
                               f"and Hyprland {installed} is installed. Windows use Hyprland's own blur until a "
                               "matching plugin comes with an update.")
        return
    if plugin.exists() and hashlib.sha256(plugin.read_bytes()).hexdigest() == sha.group(1):
        if built_for:
            stamp.write_text(built_for + "\n")
        off.unlink(missing_ok=True)
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
    # What it was built for, from the pin: not the Hyprland that happens to
    # be installed.
    if built_for:
        stamp.write_text(built_for + "\n")
    else:
        stamp.unlink(missing_ok=True)
    off.unlink(missing_ok=True)


def hyprland_release() -> str:
    """The installed Hyprland's version ("" if it can't be told)."""
    if not shutil.which("pacman"):
        return ""
    pacman = ["pacman"] if ROOT == Path("/") else ["pacman", "--sysroot", str(ROOT)]
    q = _run([*pacman, "-Q", "hyprland"])
    return q.stdout.split()[-1].split("-")[0] if q.returncode == 0 and q.stdout.split() else ""


def glass_notice(reason: str) -> str:
    """What to say when the Liquid Glass plugin couldn't be updated: whether
    the one in place was built for the Hyprland installed now."""
    plugin = path("/usr/lib/golden-gate/hyprglass.so")
    stamp = plugin.with_name(plugin.name + ".hyprland")
    now = hyprland_release()
    built = stamp.read_text().strip() if stamp.exists() else ""
    if now and built and built != now:
        return (f"The Liquid Glass plugin couldn't be updated ({reason}), and the one installed was made for "
                f"Hyprland {built}, not {now}: windows and panels may show without glass until the next update.")
    return f"The Liquid Glass plugin couldn't be updated ({reason}); the current one is still in use."


def update_hyprbars(tree: Path, emit: Emit) -> None:
    """Title bars for apps that leave theirs to the compositor: build hyprbars
    for the Hyprland installed now when it's missing or was built for another
    release (Hyprland refuses a plugin built for another). The build tools are
    installed when they aren't there. Only on the running system."""
    plugin = path("/usr/lib/golden-gate/hyprbars.so")
    stamp = plugin.with_name(plugin.name + ".hyprland")
    if ROOT != Path("/") or not plugin.parent.is_dir() or not shutil.which("pacman"):
        return
    query = _run(["pacman", "-Q", "hyprland"])
    if query.returncode != 0:
        return
    release = query.stdout.split()[-1].split("-")[0]
    if plugin.exists() and stamp.exists() and stamp.read_text().strip() == release:
        return
    emit("progress", progress=0.95, message="Building title bars for downloaded apps…", remaining=-1)
    tools = ["gcc", "make", "git", "pkgconf"]
    missing = [t for t in _run(["pacman", "-T", *tools]).stdout.split() if t]
    if missing:
        _run(["pacman", "-S", "--needed", "--noconfirm", "--noprogressbar", *missing], timeout=1800)
    proc = _run(["bash", str(tree / "scripts/build-hyprbars.sh"), str(plugin)], timeout=1800)
    if proc.returncode == 0:
        return
    if plugin.exists() and (not stamp.exists() or stamp.read_text().strip() != release):
        plugin.unlink()                         # built for another Hyprland: it would only fail to load
        stamp.unlink(missing_ok=True)
    reason = (proc.stdout + proc.stderr).strip().splitlines()[-1:] or ["unknown error"]
    emit("notice", message="Title bars for downloaded apps couldn't be built: " + reason[0][:200])


def enable_services(tree: Path):
    if not shutil.which("systemctl"):
        return
    # A mounted system is enabled offline; it starts them when it boots.
    ctl = ["systemctl"] if ROOT == Path("/") else ["systemctl", f"--root={ROOT}"]
    text = (tree / "distro/archiso/build.sh").read_text()
    for unit in sorted(set(re.findall(r'/usr/lib/systemd/system/([\w@.-]+\.service) "\$WANTS/', text))):
        if unit.startswith("gg-live") or not path("/usr/lib/systemd/system/" + unit).exists():
            continue
        if _run([*ctl, "is-enabled", unit]).stdout.strip() != "enabled":
            _run([*ctl, "enable", *(["--now"] if ROOT == Path("/") else []), unit], timeout=60)


def apply(emit: Emit) -> str:
    """As root: install the newest CitronOS. "updated", "unchanged" (already
    the newest, or it couldn't be checked: a notice says why), or "failed"
    (the download or install failed: an error says why)."""
    status = check()
    if not status["available"]:
        # Not checked (offline, no access): nothing was tried, so nothing
        # failed; Software Update says so beside the result.
        if status["error"]:
            emit("notice", message="CitronOS wasn't checked: " + status["error"])
        return "unchanged"
    src = source()
    work = Path(tempfile.mkdtemp(prefix="gg-golden-update-", dir=path("/var/tmp") if path("/var/tmp").is_dir() else None))
    try:
        emit("progress", progress=0.86, message="Downloading CitronOS…", remaining=-1)
        tree = download(src, status["latest"], work)
        version = {"repo": src["repo"], "branch": src["branch"], "commit": status["latest"],
                   "date": status.get("latestDate", ""), "subject": status.get("latestSubject", "")}
        return "updated" if install_tree(tree, version, emit, work) else "failed"
    except (GitHubError, OSError, tarfile.TarError) as e:
        emit("error", message=f"CitronOS couldn't be downloaded: {e}")
        shutil.rmtree(work, ignore_errors=True)
        return "failed"


ROLLBACK = "/var/lib/golden-gate/rollback"
JOURNAL = "/var/lib/golden-gate/update-journal.json"
# What install.sh --system replaces wholesale; everything else it writes is
# a single file. (The staged run says exactly which.)
REPLACED_TREES = ["usr/share/golden-gate/ui", "usr/share/golden-gate/apps", "usr/share/icons/GoldenGate",
                  "etc/skel/.config/quickshell/golden-gate"]


def _journal(state: str, step: str, version: dict, detail: str = "") -> None:
    """Where the last install got to, kept on disk (it outlives a crash)."""
    try:
        j = path(JOURNAL)
        j.parent.mkdir(parents=True, exist_ok=True)
        tmp = j.with_suffix(".tmp")
        tmp.write_text(json.dumps({"state": state, "step": step, "commit": version.get("commit", ""),
                                   "detail": detail, "at": datetime.now(timezone.utc).isoformat()}) + "\n")
        tmp.replace(j)
    except OSError:
        pass


def _rel(p: Path) -> str:
    """p as a path inside the system being updated ("usr/share/…")."""
    return str(p.relative_to(ROOT)) if p.is_absolute() and p.is_relative_to(ROOT) else str(p).lstrip("/")


class Rollback:
    """Everything an update is about to change, kept before it changes:
    each tree and file is copied (with its owner and mode) into ROLLBACK,
    or noted as absent, in a manifest written as it goes. undo() puts every
    one back, newest first, and removes what didn't exist before."""

    def __init__(self, where: Path):
        self.where = where
        shutil.rmtree(where, ignore_errors=True)
        (where / "saved").mkdir(parents=True)
        self.entries: list[dict] = []
        self.seen: set[str] = set()

    def _note(self, entry: dict) -> None:
        self.entries.append(entry)
        tmp = self.where / "manifest.tmp"
        tmp.write_text(json.dumps(self.entries))
        tmp.replace(self.where / "manifest.json")

    def keep(self, p: Path) -> None:
        """Keep p (a file, link or whole tree) as it is now."""
        rel = _rel(p)
        if rel in self.seen or any(rel.startswith(s + "/") for s in self.seen):
            return
        self.seen.add(rel)
        saved = self.where / "saved" / rel
        if not os.path.lexists(p):
            self._note({"path": rel, "kind": "absent"})
            return
        st = os.lstat(p)
        saved.parent.mkdir(parents=True, exist_ok=True)
        if stat.S_ISDIR(st.st_mode) and not os.path.islink(p):
            shutil.copytree(p, saved, symlinks=True)
            kind = "tree"
        else:
            shutil.copy2(p, saved, follow_symlinks=False)
            kind = "file"
        owners = {}
        if kind == "tree":
            for dirpath, dirnames, filenames in os.walk(p):
                for n in [dirpath, *[os.path.join(dirpath, x) for x in dirnames + filenames]]:
                    s2 = os.lstat(n)
                    owners[os.path.relpath(n, p)] = [s2.st_uid, s2.st_gid]
        self._note({"path": rel, "kind": kind, "uid": st.st_uid, "gid": st.st_gid, "owners": owners})

    def undo(self) -> list[str]:
        problems = []
        for e in reversed(self.entries):
            dest = path("/" + e["path"])
            try:
                if os.path.islink(dest) or dest.is_file():
                    dest.unlink()
                elif dest.is_dir():
                    shutil.rmtree(dest)
                if e["kind"] == "absent":
                    continue
                saved = self.where / "saved" / e["path"]
                dest.parent.mkdir(parents=True, exist_ok=True)
                if e["kind"] == "tree":
                    shutil.copytree(saved, dest, symlinks=True)
                else:
                    shutil.copy2(saved, dest, follow_symlinks=False)
                if os.geteuid() == 0:
                    os.lchown(dest, e["uid"], e["gid"])
                    for rel, (uid, gid) in e.get("owners", {}).items():
                        try:
                            os.lchown(os.path.join(dest, rel), uid, gid)
                        except OSError:
                            pass
            except OSError as exc:
                problems.append(f"/{e['path']}: {exc.strerror or exc}")
        return problems


def _staged_changes(stage: Path) -> tuple[list[str], list[str]]:
    """What install.sh, run into stage, would change: the trees it replaces
    whole and every other file or link it writes (paths inside the root)."""
    trees = [t for t in REPLACED_TREES if os.path.lexists(stage / t)]
    files = []
    for dirpath, dirnames, filenames in os.walk(stage):
        rel_dir = os.path.relpath(dirpath, stage)
        if any(rel_dir == t or rel_dir.startswith(t + "/") for t in trees):
            dirnames[:] = []
            continue
        for n in filenames + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
            rel = os.path.normpath(os.path.join(rel_dir, n))
            if not any(rel == t or rel.startswith(t + "/") for t in trees):
                files.append(rel)
    return trees, sorted(set(files))


def _activate(stage: Path, trees: list[str], files: list[str]) -> None:
    """Put the staged install in place, keeping what each path pointed to."""
    for t in trees:
        dest = path("/" + t)
        tmp = dest.with_name(dest.name + ".golden-gate-new")
        shutil.rmtree(tmp, ignore_errors=True)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(stage / t, tmp, symlinks=True)
        if os.path.lexists(dest):
            shutil.rmtree(dest) if dest.is_dir() and not dest.is_symlink() else dest.unlink()
        tmp.rename(dest)
    for f in files:
        dest = path("/" + f)
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_name("." + dest.name + ".golden-gate-new")
        if os.path.lexists(tmp):
            tmp.unlink()
        shutil.copy2(stage / f, tmp, follow_symlinks=False)
        os.replace(tmp, dest)


def install_tree(tree: Path, version: dict, emit: Emit, work: Path) -> bool:
    """Install CitronOS from an unpacked tree, as one transaction:

    1. the packages it needs (none missing, or nothing is changed);
    2. install.sh runs into an empty staging folder, and the result is
       checked: nothing on the system has changed yet;
    3. everything about to change is kept (Rollback): the staged trees and
       files, each account's CitronOS shell and managed settings, system
       files, plugins and boot images;
    4. then it's put in place, accounts refreshed, system files, plugins,
       services and the boot image.

    A failure at any step after 3 puts every kept path back, as it was, and
    says which step failed. Two things aren't undone, and the message says
    so when they happened: packages installed in step 1 (only ever added)
    and services turned on. The copy stays in /var/lib/golden-gate/rollback
    until the next update."""
    runtime = path("/usr/share/golden-gate")
    step = "checking the packages it needs"
    rollback = None
    services_changed = False
    try:
        _journal("installing", step, version)
        left = install_packages(tree, emit)

        step = "preparing the new version"
        _journal("installing", step, version)
        emit("progress", progress=0.92, message="Installing CitronOS…", remaining=-1)
        stage = work / "stage"
        shutil.rmtree(stage, ignore_errors=True)
        stage.mkdir(parents=True)
        proc = _run(["bash", str(tree / "scripts/install.sh"), "--system", str(stage)],
                    env={**os.environ, "GG_SKIP_BUILD": "1"}, timeout=1800, cwd=str(tree))
        if proc.returncode != 0:
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-1:] or ["unknown error"]
            raise UpdateFailed(tail[0][:200] + " Nothing was changed.")
        trees, files = _staged_changes(stage)
        missing = [t for t in ("usr/share/golden-gate/apps", "usr/share/golden-gate/ui",
                               "etc/skel/.config/quickshell/golden-gate/shell.qml") if not os.path.lexists(stage / t)]
        if missing:
            raise UpdateFailed("The new version is incomplete (" + ", ".join(missing) + "). Nothing was changed.")

        step = "keeping a copy of the current version"
        _journal("installing", step, version)
        old_skel = _snapshot_skel(work)
        rollback = Rollback(path(ROLLBACK))
        for t in trees:
            rollback.keep(path("/" + t))
        for f in files:
            rollback.keep(path("/" + f))
        rollback.keep(runtime / "version.json")
        skel = path("/etc/skel/.config")
        themes = [f"ghostty/themes/{p.name}" for p in (stage / "etc/skel/.config/ghostty/themes").glob("*")]
        for entry, home in _accounts():
            conf = home / ".config"
            rollback.keep(conf / "quickshell/golden-gate")
            for rel in MANAGED + themes:
                rollback.keep(conf / rel)
                rollback.keep(conf / (rel + ".golden-gate-new"))
        overlay = tree / "distro/archiso/overlay"
        for f in sorted(overlay.rglob("*")):
            rel = f.relative_to(overlay).as_posix()
            if not f.is_dir() and not rel.startswith(LIVE_ONLY):
                rollback.keep(path("/" + rel))
        for plugin in ("hyprglass.so", "hyprglass.so.hyprland", "hyprbars.so", "hyprbars.so.hyprland"):
            rollback.keep(path("/usr/lib/golden-gate/" + plugin))
        for image in sorted(path("/boot").glob("initramfs-*.img")) if path("/boot").is_dir() else []:
            rollback.keep(image)

        step = "installing CitronOS's files"
        _journal("installing", step, version)
        _activate(stage, trees, files)

        step = "updating your settings"
        _journal("installing", step, version)
        emit("progress", progress=0.96, message="Updating your settings…", remaining=-1)
        kept = refresh_accounts(old_skel)

        step = "installing system files"
        _journal("installing", step, version)
        apply_overlay(tree)

        try:
            update_hyprglass(tree, emit)
        except (OSError, GitHubError, urllib.error.URLError) as exc:
            emit("notice", message=glass_notice(str(exc)[:120]))
        try:
            update_hyprbars(tree, emit)
        except (OSError, subprocess.SubprocessError) as exc:
            emit("notice", message=f"Title bars for downloaded apps couldn't be built: {exc}")

        step = "turning on services"
        _journal("installing", step, version)
        services_changed = True
        enable_services(tree)
        # Installs made before the installer cleaned these up still carry
        # them; the boot image is rebuilt if it was built with archiso's hooks.
        rebuild = remove_live_leftovers(ROOT)
        ensure_keyring(ROOT)
        if rebuild and shutil.which("mkinitcpio") and path("/boot/vmlinuz-linux").exists():
            step = "rebuilding the boot image"
            _journal("installing", step, version)
            emit("progress", progress=0.98, message="Rebuilding the boot image…", remaining=-1)
            proc = _run(["mkinitcpio", "-P"] if ROOT == Path("/") else ["arch-chroot", str(ROOT), "mkinitcpio", "-P"],
                        timeout=900)
            if proc.returncode != 0:
                raise UpdateFailed(_pacman_reason(proc))

        step = "recording the version"
        (runtime / "version.json").write_text(json.dumps({
            **version, "date": version.get("date") or datetime.now(timezone.utc).isoformat(),
            "installed": datetime.now(timezone.utc).isoformat(),
        }, indent=2) + "\n")
        _journal("installed", "done", version)
        if kept:
            emit("notice", message="Kept your edited " + ", ".join(kept[:3]) + ("…" if len(kept) > 3 else "")
                 + "; the new versions are beside them as .golden-gate-new.")
        if left:
            emit("notice", message="Not installed: " + "; ".join(f"{p} ({why})" for p, why in list(left.items())[:6]))
        return True
    except (UpdateFailed, GitHubError, OSError, subprocess.SubprocessError, ValueError) as e:
        reason = str(e) or e.__class__.__name__
        after = ""
        if rollback is not None:
            problems = rollback.undo()
            if problems:
                after = (" Putting the previous version back didn't fully work (" + problems[0][:120]
                         + "); its copy is in " + str(path(ROLLBACK)) + ".")
            else:
                after = " The previous version was put back"
                left_over = (["packages it needed were added"] if step != "checking the packages it needs" else []) \
                    + (["services it turns on stay on"] if services_changed else [])
                after += (" (" + "; ".join(left_over) + ")." if left_over else ".")
        _journal("failed", step, version, reason[:300])
        emit("error", message=f"CitronOS's update didn't install (while {step}): {reason[:200]}{after}")
        return False
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ------------------------------------------------------------ from a USB stick
def _say(event, **kw):
    if kw.get("message"):
        print(("! " if event in ("error", "notice") else "› ") + kw["message"], flush=True)


def _tree_version(tree: Path) -> dict:
    """Which CitronOS a tree is: git when it's a checkout, else the record
    an update bundle (or the ISO's source) carries."""
    git = lambda *a: _run(["git", "-C", str(tree), *a]).stdout.strip()
    if git("rev-parse", "--is-inside-work-tree") == "true":
        origin = git("remote", "get-url", "origin")
        m = re.match(r"^(?:https://|git@)github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", origin)
        branch = git("rev-parse", "--abbrev-ref", "HEAD")
        return {"repo": m.group(1) if m else DEFAULT_REPO,
                "branch": branch if branch and branch != "HEAD" else DEFAULT_BRANCH,
                "commit": git("rev-parse", "HEAD"), "date": git("log", "-1", "--format=%cI"),
                "subject": git("log", "-1", "--format=%s")}
    try:
        data = json.loads((tree / "golden-gate-version.json").read_text())
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {"repo": DEFAULT_REPO, "branch": DEFAULT_BRANCH, "commit": ""}


def install_local(source: str | None = None, root: str | None = None) -> int:
    """As root: install CitronOS from a tree or bundle, onto this system or
    onto one mounted at `root`."""
    global ROOT
    if os.geteuid() != 0 and not root:
        print("Run this with sudo: it installs CitronOS for the whole system.")
        return 77
    if root:
        target = Path(root).resolve()
        if not (target / "usr/share/golden-gate").is_dir() or not (target / "etc/passwd").is_file():
            print(f"! {target} doesn't look like an installed CitronOS system.")
            return 2
        ROOT = target
    work = Path(tempfile.mkdtemp(prefix="gg-golden-update-"))
    try:
        if source is None:
            own = Path(__file__).resolve().parents[2]
            if (own / "scripts/install.sh").exists():
                source = str(own)
            elif Path("/usr/share/golden-gate/source.tar.gz").exists():
                source = "/usr/share/golden-gate/source.tar.gz"
            else:
                print("! No CitronOS source here: pass --from an update bundle or a checkout.")
                return 2
        src = Path(source)
        tree = unpack(src, work / "src") if src.is_file() else src
        if not (tree / "scripts/install.sh").exists():
            print(f"! {src} doesn't contain CitronOS.")
            return 2
        version = _tree_version(tree)
        where = f"onto {ROOT}" if ROOT != Path("/") else "on this computer"
        print(f"› Installing CitronOS {str(version.get('commit', ''))[:7] or '(unknown version)'} {where}…", flush=True)
        ok = install_tree(tree, version, _say, work)
    except (GitHubError, tarfile.TarError, OSError) as e:
        print(f"! {e}")
        ok = False
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if ok:
        print(f"› Done. CitronOS {str(version.get('commit', ''))[:7]} is installed {where}.")
        print("› Settings ▸ Software Update finds later updates on GitHub."
              + (" Restart into the installed system." if ROOT != Path("/") else " Log out and back in to finish."))
    return 0 if ok else 1


def _candidates():
    """Linux partitions holding an installed CitronOS, mounting the ones
    that aren't yet. Yields (device, mountpoint, mounted_by_us)."""
    out = _run(["lsblk", "-rpno", "PATH,FSTYPE,MOUNTPOINT", "-e", "7,11"]).stdout
    for line in out.splitlines():
        parts = line.split(" ")
        dev, fstype = parts[0], parts[1] if len(parts) > 1 else ""
        mnt = parts[2].replace("\\x20", " ") if len(parts) > 2 else ""
        if fstype not in ("ext4", "btrfs", "xfs", "f2fs") or mnt.startswith("/run/archiso"):
            continue
        ours = False
        if not mnt:
            mnt = tempfile.mkdtemp(prefix="gg-disk-")
            if _run(["mount", dev, mnt]).returncode != 0:
                os.rmdir(mnt)
                continue
            ours = True
        if mnt != "/" and Path(mnt, "usr/share/golden-gate").is_dir() and Path(mnt, "etc/passwd").is_file():
            yield dev, mnt, ours
        elif ours:
            _run(["umount", mnt])
            os.rmdir(mnt)


def update_disk() -> int:
    """From the live ISO: update the CitronOS installed on this computer."""
    if os.geteuid() != 0:
        print("Run this with sudo: sudo gg-update-disk")
        return 77
    if not Path("/usr/share/golden-gate/source.tar.gz").exists():
        print("! This CitronOS doesn't carry its source; update from a bundle with install-local --from.")
        return 2
    found = list(_candidates())
    try:
        if not found:
            print("! No installed CitronOS found on this computer's disks.")
            return 1
        for i, (dev, mnt, _) in enumerate(found, 1):
            host = (Path(mnt, "etc/hostname").read_text().strip() if Path(mnt, "etc/hostname").exists() else "?")
            try:
                ver = json.loads(Path(mnt, "usr/share/golden-gate/version.json").read_text()).get("commit", "")[:7]
            except (OSError, ValueError):
                ver = ""
            print(f"  {i}. {dev}  {host}  CitronOS {ver or '(version unknown)'}")
        new = _tree_version_from_bundle()
        pick = 1
        if len(found) > 1:
            answer = input(f"Which one? [1-{len(found)}] ").strip()
            if not answer.isdigit() or not 1 <= int(answer) <= len(found):
                print("Nothing changed.")
                return 1
            pick = int(answer)
        dev, mnt, _ = found[pick - 1]
        if input(f"Update {dev} to CitronOS {new}? Accounts and files are kept. [y/N] ").strip().lower() not in ("y", "yes"):
            print("Nothing changed.")
            return 1
        return install_local("/usr/share/golden-gate/source.tar.gz", mnt)
    finally:
        for _, mnt, ours in found:
            if ours:
                _run(["umount", mnt])
                try:
                    os.rmdir(mnt)
                except OSError:
                    pass


def _tree_version_from_bundle() -> str:
    try:
        with tarfile.open("/usr/share/golden-gate/source.tar.gz") as tar:
            for m in tar:
                if m.name.endswith("/golden-gate-version.json") and m.name.count("/") == 1:
                    return json.load(tar.extractfile(m)).get("commit", "")[:7] or "(this ISO's)"
    except (OSError, tarfile.TarError, ValueError, AttributeError):
        pass
    return "(this ISO's)"


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Install CitronOS updates without GitHub.")
    sub = parser.add_subparsers(dest="command", required=True)
    local = sub.add_parser("install-local", help="install from a checkout or update bundle")
    local.add_argument("--from", dest="source", help="a checkout or golden-gate-update.tar.gz")
    local.add_argument("--root", help="a mounted CitronOS system to update instead of this one")
    sub.add_parser("update-disk", help="from the live ISO: update the CitronOS on this computer's disk")
    args = parser.parse_args()
    raise SystemExit(install_local(args.source, args.root) if args.command == "install-local" else update_disk())
