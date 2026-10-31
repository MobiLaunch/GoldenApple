"""CitronOS updates from GitHub, for Software Update.

CitronOS itself (the shell, the apps, the themes) comes from its GitHub
repository rather than from Arch's repositories: Software Update builds its
packages from what it downloads. Updates come from one of three
channels (/etc/golden-gate/update.json "channel"):

  stable  (the default) the newest GitHub release that isn't a pre-release
  beta    the newest release, pre-releases included
  dev     the newest commit of a branch, unsigned: for CitronOS's developers

A release is installed only if it is signed by a CitronOS release key this
system already trusts (release-keys/*.pem beside this file): its signed
manifest names the bundle's SHA-256, its tag and its version, and a version
older than the installed one is refused. Only an administrator, with their
password, can switch to dev (update-source-helper.py). Then:

  1. download the signed release bundle, or on dev that exact commit's
     snapshot (GitHub's tarball of the commit)
  2. install any packages the new package list adds (official repos only)
  3. build CitronOS's own packages from it (packaging/citronos, makepkg as
     its own account) and install them with pacman -U, with everything they change
     kept aside (files and pacman's own records of them) and put back if the
     install fails; the first time, over a system scripts/install.sh made,
     its files go aside for the packages' and its leftovers are removed.
     (A version from before the packages runs its scripts/install.sh --system.)
  4. bring every account's own copies up to date: the Hyprland, GTK, Ghostty
     and font files, but only those the user hasn't changed; an edited file is
     left alone and the new one is written next to it as NAME.golden-gate-new.
     An account's copy of the shell goes (the system's, /etc/xdg, is the one),
     and so do the copies of files that are now the system's, unless edited
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
import gzip
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
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

API = os.environ.get("GG_UPDATE_API", "https://api.github.com").rstrip("/")
ROOT = Path(os.environ.get("GG_UPDATE_ROOT", "/"))
DEFAULT_REPO = "MobiLaunch/GoldenApple"
# Development happens here; main gets it when the work is merged.
DEFAULT_BRANCH = "claude/linux-macos-golden-gate-ui-pckc7s"
CHANNELS = ("stable", "beta", "dev")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
VERSION_RE = re.compile(r"^v?(\d{1,4})\.(\d{1,4})(?:\.(\d{1,4}))?(?:-([0-9A-Za-z.-]{1,40}))?$")
# Public keys whose signature makes a release genuine. Tests (only with a
# staging root) may point elsewhere; pkexec and sudo clear the environment.
RELEASE_KEYS = Path(os.environ["GG_RELEASE_KEYS"]) if os.environ.get("GG_RELEASE_KEYS") and os.environ.get("GG_UPDATE_ROOT") \
    else Path(__file__).resolve().parent / "release-keys"
BRANCH_RE = re.compile(r"^(?!.*\.\.)[A-Za-z0-9_./-]{1,200}$")

# Files every account gets from /etc/skel/.config that CitronOS keeps current.
MANAGED = [
    "hypr/hyprland.conf", "hypr/hypridle.conf", "hypr/golden-gate/motion.conf",
    "hypr/golden-gate/report-config-errors.sh", "hypr/golden-gate/machine-conf.sh",
    "hypr/golden-gate/windows.conf",
    "gtk-4.0/gtk.css", "gtk-3.0/gtk.css", "fontconfig/conf.d/60-golden-gate.conf",
    "ghostty/config",
]
# What scripts/install.sh gave every account that is now the system's (the
# packages'): removed from an account that has it as it came, unless the
# account's hyprland.conf still uses it.
RETIRED = [
    "hypr/golden-gate/motion.conf", "hypr/golden-gate/report-config-errors.sh",
    "hypr/golden-gate/machine-conf.sh", "fontconfig/conf.d/60-golden-gate.conf",
    "systemd/user/citronpods-daemon.service", "systemd/user/citronpods-engine-bootstrap.service",
    "systemd/user/citronpods-engine-bootstrap.path",
]
SYSTEM_SHELL = "/etc/xdg/quickshell/golden-gate"

# CitronOS's packages (packaging/citronos/PKGBUILD), and where the ones built
# for an update are kept: inside the system they're for, where pacman
# --sysroot reads them.
PACKAGES = ("citronos-runtime", "citronos-shell", "citronos-hyprland-config", "citronos-theme", "citronos")
PACKAGE_RE = re.compile(r"^(citronos(?:-[a-z-]+)?)-([^-/]+)-([^-/]+)-any\.pkg\.tar\.\w+$")
PACKAGE_CACHE = "/var/cache/golden-gate/packages"
# Who builds them: makepkg won't build as root, and an account of its own,
# rather than nobody, so no other service can change the verified sources
# while they're built.
BUILD_USER = "citronos-build"
# Kept whole by the rollback, each a few hundred files or more that are all
# CitronOS's; the packages' other files are kept one by one.
PACKAGED_TREES = ["usr/share/golden-gate/ui", "usr/share/golden-gate/apps", "usr/share/golden-gate/hypr",
                  "etc/xdg/quickshell/golden-gate", "usr/share/icons/GoldenGate", "usr/share/sddm/themes/golden-gate"]
# What scripts/install.sh --system wrote that no package has (tests/packaging.py
# checks the list against it), plus /usr/local/bin's gg-* commands that are in
# /usr/bin now: removed once the packages are installed, unless one owns it.
INSTALL_SH_LEFTOVERS = (
    "etc/skel/.config/quickshell",                    # the shell: /etc/xdg's
    "etc/skel/.config/hypr/golden-gate",              # made per account by gg-session
    "etc/skel/.config/mimeapps.list",                 # /etc/xdg/mimeapps.list
    "etc/skel/.config/fontconfig/conf.d/60-golden-gate.conf",
    "etc/skel/.config/systemd/user/citronpods-daemon.service",
    "etc/skel/.config/systemd/user/citronpods-engine-bootstrap.service",
    "etc/skel/.config/systemd/user/citronpods-engine-bootstrap.path",
    "etc/systemd/user/default.target.wants/citronpods-engine-bootstrap.service",
    "etc/systemd/user/default.target.wants/citronpods-engine-bootstrap.path",
    "usr/share/golden-gate/runtime",                  # helpers: /usr/lib/golden-gate
    "usr/share/licenses/golden-gate",
    # Copies of the packaged hooks, which would stand in for them for good.
    "etc/pacman.d/hooks/citronos-release.hook",
    "etc/pacman.d/hooks/citronos-pacman.hook",
)
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
    if not isinstance(cfg, dict):
        cfg = {}
    built = installed()
    repo = cfg.get("repo") or built.get("repo") or DEFAULT_REPO
    branch = cfg.get("branch") or built.get("branch") or DEFAULT_BRANCH
    # Signed releases unless an administrator chose otherwise. A file from
    # before channels existed (it could be written without a password then)
    # counts as stable.
    channel = cfg.get("channel") if cfg.get("channel") in CHANNELS else "stable"
    token = ""
    try:
        token = path("/etc/golden-gate/update-token").read_text().strip()
    except OSError:
        pass
    return {"repo": repo if REPO_RE.match(repo) else DEFAULT_REPO,
            "branch": branch if BRANCH_RE.match(branch) else DEFAULT_BRANCH,
            "channel": channel, "token": token}


def set_source(repo: str, branch: str, token: str | None, channel: str = "stable") -> None:
    """As root: save the repository, branch, channel and (when given) token."""
    if not REPO_RE.match(repo):
        raise ValueError("The repository should look like owner/name.")
    if not BRANCH_RE.match(branch):
        raise ValueError("That isn't a valid branch name.")
    if channel not in CHANNELS:
        raise ValueError("Choose Stable, Beta or Development.")
    if token is not None:
        token = clean_token(token)
    folder = path("/etc/golden-gate")
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "update.json").write_text(json.dumps({"repo": repo, "branch": branch, "channel": channel}, indent=2) + "\n")
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


def verify_source(repo: str, branch: str, token: str, channel: str = "dev") -> tuple[str, bool] | None:
    """None when GitHub serves `repo` (on dev, its `branch`) with this token;
    otherwise refusal()'s reason, and whether the token is what has to change."""
    if not REPO_RE.match(repo) or not BRANCH_RE.match(branch):
        return None                     # set_source says what's wrong with them
    try:
        api(f"/repos/{repo}/commits/{branch}" if channel == "dev" else f"/repos/{repo}", token)
    except GitHubError as e:
        message, token_problem = refusal(e, {"repo": repo, "branch": branch, "token": token})
        missing_branch = e.status == 404 and "no branch named" in message
        return message, token_problem or missing_branch
    return None


def version_key(text: str) -> tuple | None:
    """A release's version as a sortable tuple, or None if it isn't one.
    4.0 == 4.0.0; a pre-release (4.1.0-beta.2) sorts before its release."""
    m = VERSION_RE.match(str(text or "").strip())
    if not m:
        return None
    pre = m.group(4)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0), 0 if pre else 1, pre or "")


def check() -> dict:
    """What Software Update shows for CitronOS."""
    src = source()
    now = installed()
    out = {"repo": src["repo"], "branch": src["branch"], "channel": src["channel"],
           "signed": src["channel"] != "dev", "current": now.get("commit", ""),
           "currentVersion": now.get("version", ""), "currentDate": now.get("date", ""),
           "available": False, "notes": [], "ahead": 0, "needsToken": False, "error": "", "note": ""}
    token_file = path("/etc/golden-gate/update-token")
    if not src["token"] and token_file.exists():
        out["error"] = ("A token is saved, but this account can't read it. "
                        "Only administrators can check for CitronOS updates.")
        return out
    if src["channel"] != "dev":
        return _check_release(src, now, out)
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


def _latest_release(src: dict) -> dict | None:
    """The newest published release on the source's channel."""
    for rel in api(f"/repos/{src['repo']}/releases?per_page=30", src["token"]) or []:
        if not isinstance(rel, dict) or rel.get("draft") or version_key(rel.get("tag_name")) is None:
            continue
        if src["channel"] == "stable" and rel.get("prerelease"):
            continue
        return rel
    return None


def _check_release(src: dict, now: dict, out: dict) -> dict:
    try:
        rel = _latest_release(src)
    except GitHubError as e:
        out["error"], out["needsToken"] = refusal(e, src)
        return out
    if rel is None:
        out["note"] = ("No CitronOS beta or release has been published yet." if src["channel"] == "beta"
                       else "No CitronOS release has been published yet.")
        return out
    tag = str(rel["tag_name"])
    body = [l.strip().lstrip("-*• ").strip() for l in str(rel.get("body") or "").splitlines()]
    out.update(latest=tag, latestVersion=tag.lstrip("v"), latestDate=rel.get("published_at") or "",
               latestSubject=str(rel.get("name") or "CitronOS " + tag.lstrip("v"))[:200],
               notes=[l[:200] for l in body if l and not l.startswith("#")][:20])
    mine = version_key(now.get("version", ""))
    # An install without a version record predates signed releases: any
    # release supersedes it.
    out["available"] = mine is None or version_key(tag) > mine
    return out


class UpdateRefused(Exception):
    """A release that isn't genuine, or isn't newer: never installed."""


def verify_signature(data: bytes, signature: bytes) -> bool:
    """True when one of this system's release keys signed `data` (Ed25519)."""
    keys = sorted(RELEASE_KEYS.glob("*.pem")) if RELEASE_KEYS.is_dir() else []
    if not keys:
        raise UpdateRefused("This CitronOS has no release key, so it can't tell a genuine update from a fake one.")
    with tempfile.TemporaryDirectory(prefix="gg-verify-") as d:
        msg, sig = Path(d) / "manifest", Path(d) / "manifest.sig"
        msg.write_bytes(data)
        sig.write_bytes(signature)
        for key in keys:
            proc = _run(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(key), "-rawin",
                         "-in", str(msg), "-sigfile", str(sig)])
            if proc.returncode == 0 and "Signature Verified Successfully" in proc.stdout:
                return True
    return False


def check_bundle(bundle: Path, manifest: bytes, signature: bytes, installed_version: str = "",
                 tag: str = "", channel: str = "stable") -> dict:
    """The manifest of a signed bundle, once everything about it checks out:
    signed by a release key, for this very file (name and SHA-256), the
    release it claims to be, on a channel this system takes, and newer than
    what's installed. Raises UpdateRefused otherwise."""
    if not verify_signature(manifest, signature):
        raise UpdateRefused("This update isn't signed by CitronOS, so it wasn't installed.")
    try:
        info = json.loads(manifest.decode("utf-8"))
    except ValueError:
        raise UpdateRefused("The update's manifest is damaged.")
    if not isinstance(info, dict) or info.get("format") != 1 or version_key(info.get("version")) is None:
        raise UpdateRefused("The update's manifest isn't one this CitronOS understands.")
    digest = hashlib.sha256()
    with open(bundle, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    if info.get("file") != bundle.name or info.get("sha256") != digest.hexdigest():
        raise UpdateRefused("The update's file isn't the one CitronOS signed: it may have been changed.")
    if tag and info.get("tag") != tag:
        raise UpdateRefused("The update is signed as a different release than the one offered.")
    allowed = {"stable": ("stable",), "beta": ("stable", "beta")}.get(channel, ("stable", "beta", "dev"))
    if info.get("channel") not in allowed:
        raise UpdateRefused(f"The update is a {info.get('channel')} build; this computer takes {channel} updates.")
    mine = version_key(installed_version)
    if mine is not None and version_key(info["version"]) <= mine:
        raise UpdateRefused(f"CitronOS {info['version']} isn't newer than the installed {installed_version}.")
    return info


class _NoAuthOnRedirect(urllib.request.HTTPRedirectHandler):
    """GitHub serves release assets from another host: the token stays with GitHub."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and urllib.parse.urlsplit(newurl).netloc != urllib.parse.urlsplit(req.full_url).netloc:
            new.remove_header("Authorization")
        return new


def _asset(src: dict, asset: dict, into: Path, limit: int) -> Path:
    dest = into / Path(str(asset.get("name"))).name
    headers = {"Accept": "application/octet-stream", "User-Agent": "golden-gate-update"}
    if src["token"]:
        headers["Authorization"] = f"Bearer {src['token']}"
    url = asset.get("url") or f"{API}/repos/{src['repo']}/releases/assets/{asset.get('id')}"
    try:
        opener = urllib.request.build_opener(_NoAuthOnRedirect)
        with opener.open(urllib.request.Request(url, headers=headers), timeout=120) as r, open(dest, "wb") as f:
            size = 0
            for block in iter(lambda: r.read(1 << 20), b""):
                size += len(block)
                if size > limit:
                    raise GitHubError(0, f"{dest.name} is larger than a CitronOS update can be.")
                f.write(block)
    except urllib.error.HTTPError as e:
        raise GitHubError(e.code, f"Couldn't download {dest.name} ({e.code}).")
    except (urllib.error.URLError, OSError) as e:
        raise GitHubError(0, f"Couldn't download {dest.name}: {getattr(e, 'reason', e)}")
    return dest


def download_release(src: dict, tag: str, into: Path) -> tuple[Path, dict]:
    """The signed bundle of release `tag`, checked and unpacked; returns its
    top folder and its manifest."""
    rel = api(f"/repos/{src['repo']}/releases/tags/{urllib.parse.quote(tag, safe='')}", src["token"])
    name = "citronos-" + tag.lstrip("v")
    assets = {a.get("name"): a for a in rel.get("assets") or [] if isinstance(a, dict)}
    missing = [n for n in (name + ".tar.gz", name + ".manifest.json", name + ".manifest.json.sig") if n not in assets]
    if missing:
        raise UpdateRefused(f"Release {tag} isn't a signed CitronOS release (it has no {missing[0]}).")
    manifest = _asset(src, assets[name + ".manifest.json"], into, 1 << 16).read_bytes()
    signature = _asset(src, assets[name + ".manifest.json.sig"], into, 1 << 12).read_bytes()
    # The manifest's signature is checked before the large download.
    if not verify_signature(manifest, signature):
        raise UpdateRefused("This update isn't signed by CitronOS, so it wasn't installed.")
    bundle = _asset(src, assets[name + ".tar.gz"], into, 2 << 30)
    info = check_bundle(bundle, manifest, signature, installed().get("version", ""), tag, src["channel"])
    return unpack(bundle, into / "src"), info


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
    reason = (errors or lines or ["pacman exited with status %d" % proc.returncode])[-1]
    # Which ones, when pacman only says it "could not satisfy dependencies".
    unmet = [m.group(1) for l in lines for m in [re.search(r"unable to satisfy dependency '([^']+)'", l)] if m]
    if unmet:
        reason += ": " + ", ".join(dict.fromkeys(unmet))
    return reason[:200]


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


def _pacman() -> list[str]:
    return ["pacman"] if ROOT == Path("/") else ["pacman", "--sysroot", str(ROOT)]


def _paths(proc: subprocess.CompletedProcess, dirs: bool = False) -> list[str]:
    """pacman -Ql's paths, inside the system ("usr/share/…"); directories
    (they end in /) only when asked for, still ending in /."""
    out = []
    for line in proc.stdout.splitlines():
        line = line.strip().lstrip("/")
        if line and (dirs or not line.endswith("/")):
            out.append(line)
    return out


def packaged(tree: Path) -> bool:
    """Is this version of CitronOS installed as its packages (T-2.1)?"""
    return (tree / "packaging/citronos/PKGBUILD").is_file() and bool(shutil.which("pacman")) \
        and path("/var/lib/pacman/local").is_dir()


def _packages_installed() -> bool:
    return any(path("/var/lib/pacman/local").glob("citronos-runtime-*"))


def package_version(tree: Path, version: dict) -> str:
    """The packages' version: Release.qml's, then when and which commit, as
    the ISO's are (citronos_pkgver in distro/archiso/build.sh), so that pacman
    orders them as they came."""
    try:
        m = re.search(r'property string version: "([^"]+)"', (tree / "apps/lib/theme/Release.qml").read_text())
    except OSError:
        m = None
    release = re.sub(r"[^A-Za-z0-9.]", ".", m.group(1)) if m else "0"
    try:
        when = datetime.fromisoformat(str(version.get("date") or "").replace("Z", "+00:00"))
        when = (when if when.tzinfo else when.replace(tzinfo=timezone.utc)).astimezone(timezone.utc)
    except ValueError:
        when = datetime.now(timezone.utc)
    commit = str(version.get("commit") or "")
    commit = commit[:7] if re.fullmatch(r"[0-9a-f]{7,40}", commit) else "unknown"
    return f"{release}.r{when:%Y%m%d%H%M%S}.g{commit}"


def _build_copy(top: Path):
    """What the build's copy of the tree leaves out: what git doesn't track
    there (the PKGBUILD's own build folders and earlier builds included)."""
    def ignore(d, names):
        rel = os.path.relpath(d, top)
        out = {n for n in names if n == "__pycache__" or ".pkg.tar." in n}
        if rel == ".":
            out |= {".git", "node_modules", "out"} & set(names)
        elif rel == "distro":
            out |= {"work", "localrepo"} & set(names)
        elif rel == os.path.join("packaging", "citronos"):
            out |= {"src", "pkg"} & set(names)
        return out
    return ignore


def _builder() -> pwd.struct_passwd:
    """BUILD_USER, made the first time it's needed (on the computer that
    builds: with --root, the live ISO's)."""
    try:
        return pwd.getpwnam(BUILD_USER)
    except KeyError:
        _run(["useradd", "--system", "--no-create-home", "--home-dir", "/", "--shell", "/usr/bin/nologin",
              "--comment", "Builds CitronOS's packages for Software Update", BUILD_USER])
    try:
        return pwd.getpwnam(BUILD_USER)
    except KeyError:
        raise UpdateFailed(f"The account that builds CitronOS ({BUILD_USER}) couldn't be made. Nothing was changed.")


def build_packages(tree: Path, version: dict, work: Path, emit: Emit) -> list[Path]:
    """CitronOS's packages, built from the tree (packaging/citronos): by
    makepkg as BUILD_USER, in a copy of the tree only it can change. They're
    kept in PACKAGE_CACHE, for pacman."""
    missing = [t for t in ("makepkg", "make", "fakeroot", "node", "rsvg-convert") if not shutil.which(t)]
    if missing:
        raise UpdateFailed("Building CitronOS needs " + ", ".join(missing) + ", which isn't installed. Nothing was changed.")
    emit("progress", progress=0.9, message="Building CitronOS…", remaining=-1)
    build = work / "build"
    shutil.rmtree(build, ignore_errors=True)
    shutil.copytree(tree, build, symlinks=True, ignore=_build_copy(tree))
    here = build / "packaging/citronos"
    env = {"PATH": "/usr/bin:/bin", "HOME": str(build), "LANG": "C.UTF-8",
           "CITRONOS_PKGVER": package_version(tree, version)}
    who = {}
    if os.geteuid() == 0:
        builder = _builder()
        os.chmod(work, 0o711)                   # the builder passes through to its copy
        _chown_tree(build, builder.pw_uid, builder.pw_gid)
        os.chmod(build, 0o700)
        who = {"user": builder.pw_uid, "group": builder.pw_gid, "extra_groups": []}
    proc = _run(["makepkg", "-d", "--noconfirm", "--nocolor"], cwd=str(here), env=env, timeout=3600, **who)
    built = sorted(p for p in here.glob("*.pkg.tar.*") if PACKAGE_RE.match(p.name))
    names = {PACKAGE_RE.match(p.name).group(1) for p in built}
    if proc.returncode != 0 or names != set(PACKAGES):
        lines = [l for l in (proc.stdout + proc.stderr).strip().splitlines() if l.strip()]
        errors = [l for l in lines if "ERROR" in l or "error" in l.lower()]
        why = ((errors or lines or [f"makepkg made {len(names)} of {len(PACKAGES)} packages"])[-1]).strip()[:200]
        raise UpdateFailed(f"CitronOS's packages couldn't be built ({why}). Nothing was changed.")
    cache = path(PACKAGE_CACHE)
    shutil.rmtree(cache, ignore_errors=True)
    cache.mkdir(parents=True)
    out = []
    for p in built:
        shutil.copy2(p, cache / p.name)
        out.append(cache / p.name)
    return out


def package_plan(built: list[Path]) -> dict:
    """What installing the built packages changes: the files of the
    CitronOS packages installed now ("old") and of the new ones ("new"),
    pacman's records of both ("db"), and the files in the way: ones that
    aren't any package's (scripts/install.sh's, the first time) where a new
    package has a file. Nothing is changed yet."""
    pacman = _pacman()
    inside = ["/" + _rel(p) for p in built]       # pacman --sysroot reads them inside the root
    have = [n for n in _run([*pacman, "-Qq"]).stdout.split() if n in PACKAGES]
    old = set(_paths(_run([*pacman, "-Qlq", *have]))) if have else set()
    new: set[str] = set()
    for p in inside:
        q = _run([*pacman, "-Qlpq", p])
        if q.returncode != 0:
            raise UpdateFailed("A package built from this version can't be read (" + _pacman_reason(q) + "). Nothing was changed.")
        new |= set(_paths(q))
    local = path("/var/lib/pacman/local")
    db = sorted(_rel(d) for d in local.glob("citronos*") if d.is_dir())
    for p in built:
        m = PACKAGE_RE.match(p.name)
        db.append(_rel(local / f"{m.group(1)}-{m.group(2)}-{m.group(3)}"))
    candidates = [f for f in sorted(new - old) if os.path.lexists(path("/" + f))]
    in_the_way = []
    if candidates:
        owned = _owned()
        in_the_way = [f for f in candidates if f not in owned and f + "/" not in owned]
    return {"packages": inside, "installed": have, "old": old, "new": new, "db": db, "in_the_way": in_the_way}


def keep_for_packages(rollback: "Rollback", plan: dict) -> None:
    """Keep everything installing the packages changes (each tree whole)."""
    for t in PACKAGED_TREES:
        rollback.keep(path("/" + t))
    for f in sorted(plan["old"] | plan["new"]):
        rollback.keep(path("/" + f))
        if f.startswith("etc/"):
            rollback.keep(path("/" + f + ".pacnew"))   # a backup file the user changed
    for d in plan["db"]:
        rollback.keep(path("/" + d))
    rollback.keep(path("/usr/lib/os-release"))


def install_built(plan: dict) -> None:
    """pacman -U the built packages, the files in their way set aside first
    (kept by the rollback), and the system named for the new version."""
    for f in plan["in_the_way"]:
        p = path("/" + f)
        shutil.rmtree(p) if p.is_dir() and not p.is_symlink() else p.unlink()
    proc = _run([*_pacman(), "-U", "--noconfirm", "--noprogressbar", *plan["packages"]], timeout=1800)
    if proc.returncode != 0:
        raise UpdateFailed("CitronOS's packages didn't install: " + _pacman_reason(proc))
    # The packaged hook does this when pacman upgrades os-release; the version
    # in it is the packages', which hooks read before they were installed.
    named = path("/usr/share/golden-gate/os-release")
    if named.is_file() and path("/usr/lib").is_dir():
        shutil.copyfile(named, path("/usr/lib/os-release"))
        os.chmod(path("/usr/lib/os-release"), 0o644)


def _mtree_dirs(mtree: Path) -> dict[str, int]:
    """The folders a package's mtree (pacman's record of it) has, with
    their modes, inside the system."""
    out, defaults = {}, {}
    with gzip.open(mtree, "rt", errors="replace") as f:
        for line in f:
            words = line.split()
            if not words or words[0].startswith("#"):
                continue
            keys = dict(w.split("=", 1) for w in words[1:] if "=" in w)
            if words[0] == "/set":
                defaults.update(keys)
                continue
            keys = {**defaults, **keys}
            if keys.get("type") == "dir" and "mode" in keys and words[0].startswith("./"):
                name = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), words[0][2:])
                out[name] = int(keys["mode"], 8)
    return out


def match_folder_modes(rollback: "Rollback") -> None:
    """pacman leaves a folder that's already there as it is: one install.sh
    made with another mode (/etc/sudoers.d, 755 where the package has 750)
    stays so, and pacman -Qkk says so. Each CitronOS package's folders get
    the mode it has (the old one kept)."""
    for record in sorted(path("/var/lib/pacman/local").glob("citronos*/mtree")):
        try:
            folders = _mtree_dirs(record)
        except (OSError, EOFError, ValueError):
            continue
        for rel, mode in folders.items():
            p = path("/" + rel)
            if p.is_dir() and not p.is_symlink() and stat.S_IMODE(p.stat().st_mode) != mode:
                rollback.keep_mode(p)
                os.chmod(p, mode)


def install_sh_leftovers(tree: Path, plan: dict) -> list[str]:
    """What scripts/install.sh left that the packages don't need, and that
    no package or the overlay has: INSTALL_SH_LEFTOVERS, and the gg-*
    commands in /usr/local/bin that the packages have in /usr/bin."""
    commands = ["usr/local/" + f[len("usr/"):] for f in plan["new"] if re.match(r"^usr/bin/gg-[\w.-]+$", f)]
    there = [rel for rel in [*INSTALL_SH_LEFTOVERS, *sorted(commands)]
             if os.path.lexists(path("/" + rel)) and not (tree / "distro/archiso/overlay" / rel).exists()]
    if not there:
        return []
    owned = _owned()
    return [rel for rel in there if rel not in owned and rel + "/" not in owned]


def _owned() -> set[str]:
    """Every path a package has, inside the system; folders end in /."""
    return set(_paths(_run([*_pacman(), "-Qlq"]), dirs=True))


def remove_leftovers(leftovers: list[str]) -> None:
    """Remove them (kept by the rollback), and the folders that leaves
    empty, up to one a package has."""
    if not leftovers:
        return
    owned = _owned()
    for rel in leftovers:
        p = path("/" + rel)
        if p.is_dir() and not p.is_symlink():
            shutil.rmtree(p)
        elif os.path.lexists(p):
            p.unlink()
        for parent in Path(rel).parents:
            d = path("/" + str(parent))
            if str(parent) + "/" in owned or len(parent.parts) < 2 or not d.is_dir() or any(d.iterdir()):
                break
            d.rmdir()


def _snapshot_skel(into: Path) -> Path:
    keep = into / "old-skel"
    skel = path("/etc/skel/.config")
    for rel in MANAGED + RETIRED + [f"ghostty/themes/{p.name}" for p in (skel / "ghostty/themes").glob("*")]:
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
        # A CitronOS account: one with its own copy of the shell (before the
        # packages), its settings, or the hyprland.conf every account gets.
        conf = home / ".config"
        if os.path.lexists(conf / "quickshell/golden-gate") or (conf / "golden-gate").is_dir() \
                or (conf / "hypr/hyprland.conf").is_file():
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


def refresh_accounts(old_skel: Path, packaged: bool = False) -> list[str]:
    """Bring each account's copies up to date. Returns files left alone."""
    skel = path("/etc/skel/.config")
    kept = []
    themes = [f"ghostty/themes/{p.name}" for p in (skel / "ghostty/themes").glob("*")]
    for entry, home in _accounts():
        conf = home / ".config"
        shell = conf / "quickshell/golden-gate"
        fresh = skel / "quickshell/golden-gate"
        if packaged:
            # The system's shell is the one. The account's copy goes, and a
            # link to the system's stands in until the next login (gg-session
            # removes it), so the shell running now reloads into the new one
            # rather than losing its files.
            if path(SYSTEM_SHELL).is_dir() and shell.is_dir() and not shell.is_symlink():
                shutil.rmtree(shell)
                shell.symlink_to(SYSTEM_SHELL)
                if os.geteuid() == 0:
                    os.lchown(shell, entry.pw_uid, entry.pw_gid)
        elif fresh.is_dir():
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
        if packaged:
            hypr = conf / "hypr/hyprland.conf"
            uses = hypr.read_text(errors="replace") if hypr.is_file() else ""
            for rel in RETIRED:
                mine, old = conf / rel, old_skel / rel
                if (skel / rel).exists() or Path(rel).name in uses:
                    continue
                if mine.is_file() and not mine.is_symlink() and old.is_file() and filecmp.cmp(mine, old, shallow=False):
                    mine.unlink()
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


HYPRLAND_ARCHIVE = "https://archive.archlinux.org/packages/h/hyprland/"


def hold_hyprland(tree: Path, emit: Emit | None = None) -> None:
    """The Hyprland CitronOS's desktop is made for (HYPRGLASS_HYPRLAND in
    build.sh, what its glass is built for too), held there: pacman.conf's
    IgnorePkg (pacman-config.sh), and that version installed if another is,
    from pacman's cache or else the Arch Linux Archive (pacman checks its
    signature either way). Hyprland 0.57 no longer reads hyprland.conf: a
    system that took it from the mirrors before the hold has no desktop
    until this puts 0.56.2 back."""
    emit = emit or (lambda *a, **k: None)
    script = tree / "apps/setup/pacman-config.sh"
    if script.is_file():
        _run(["sh", str(script), "" if ROOT == Path("/") else str(ROOT)])
    text = (tree / "distro/archiso/build.sh").read_text() if (tree / "distro/archiso/build.sh").is_file() else ""
    want = re.search(r'^HYPRGLASS_HYPRLAND="?([0-9][^"\s]*)"?', text, re.M)
    installed = hyprland_release()
    if not want or not installed or installed == want.group(1):
        return
    want = want.group(1)
    cached = sorted(path("/var/cache/pacman/pkg").glob(f"hyprland-{want}-*-x86_64.pkg.tar.zst"),
                    key=lambda p: int(re.search(r"-(\d+)-x86_64", p.name).group(1)))
    if cached:
        package = str(cached[-1])
    else:
        with urllib.request.urlopen(HYPRLAND_ARCHIVE, timeout=30) as r:
            names = re.findall(rf'hyprland-{re.escape(want)}-(\d+)-x86_64\.pkg\.tar\.zst"', r.read().decode(errors="replace"))
        if not names:
            raise OSError(f"Hyprland {want} isn't in the Arch Linux Archive")
        package = f"{HYPRLAND_ARCHIVE}hyprland-{want}-{max(map(int, names))}-x86_64.pkg.tar.zst"
    pacman = ["pacman"] if ROOT == Path("/") else ["pacman", "--sysroot", str(ROOT)]
    emit("progress", progress=0.97, message=f"Installing Hyprland {want}…", remaining=-1)
    proc = _run([*pacman, "-U", "--noconfirm", "--noprogressbar", package], timeout=900)
    if proc.returncode != 0:
        raise OSError(_pacman_reason(proc))
    emit("notice", message=f"Hyprland {installed} came from the package mirrors, but CitronOS's desktop is made "
                           f"for Hyprland {want}, so that's installed again and kept until CitronOS supports a newer one.")


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
        elif status.get("note"):
            emit("notice", message=status["note"])
        return "unchanged"
    src = source()
    work = Path(tempfile.mkdtemp(prefix="gg-golden-update-", dir=path("/var/tmp") if path("/var/tmp").is_dir() else None))
    try:
        emit("progress", progress=0.86, message="Downloading CitronOS…", remaining=-1)
        if src["channel"] == "dev":
            tree = download(src, status["latest"], work)
            version = {"repo": src["repo"], "branch": src["branch"], "channel": "dev", "commit": status["latest"],
                       "date": status.get("latestDate", ""), "subject": status.get("latestSubject", "")}
        else:
            tree, info = download_release(src, status["latest"], work)
            version = {"repo": src["repo"], "channel": src["channel"], "version": info["version"],
                       "tag": info.get("tag", status["latest"]), "commit": str(info.get("commit", "")),
                       "date": str(info.get("date", "")) or status.get("latestDate", ""),
                       "subject": status.get("latestSubject", "")}
        return "updated" if install_tree(tree, version, emit, work) else "failed"
    except UpdateRefused as e:
        emit("error", message=str(e))
        shutil.rmtree(work, ignore_errors=True)
        return "failed"
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
        if rel in self.seen or any(str(parent) in self.seen for parent in Path(rel).parents):
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

    def keep_mode(self, p: Path) -> None:
        """Keep a folder's mode (only: what's in it is kept, or not, apart)."""
        self._note({"path": _rel(p), "kind": "mode", "mode": stat.S_IMODE(os.lstat(p).st_mode)})

    def undo(self) -> list[str]:
        problems = []
        for e in reversed(self.entries):
            dest = path("/" + e["path"])
            try:
                if e["kind"] == "mode":
                    os.chmod(dest, e["mode"])
                    continue
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
    2. CitronOS's own packages are built from it (a version from before
       them: its install.sh runs into an empty staging folder instead), and
       what installing them changes is worked out: nothing on the system has
       changed yet;
    3. everything about to change is kept (Rollback): the packages' files,
       old and new, and pacman's records of them (or the staged trees and
       files), install.sh's leftovers, each account's CitronOS shell and
       managed settings, system files, plugins and boot images;
    4. then it's put in place (pacman -U), leftovers removed, accounts
       refreshed, system files, plugins, services and the boot image.

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
        as_packages = packaged(tree)
        if as_packages:
            built = build_packages(tree, version, work, emit)
            emit("progress", progress=0.92, message="Installing CitronOS…", remaining=-1)
            plan = package_plan(built)
            leftovers = install_sh_leftovers(tree, plan)
            themes = [f[len("etc/skel/.config/"):] for f in plan["new"] if f.startswith("etc/skel/.config/ghostty/themes/")]
        else:
            if _packages_installed():
                raise UpdateFailed("This version of CitronOS is older than its packages, which are installed here, "
                                   "so it can't be installed over them. Nothing was changed.")
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
            themes = [f"ghostty/themes/{p.name}" for p in (stage / "etc/skel/.config/ghostty/themes").glob("*")]

        step = "keeping a copy of the current version"
        _journal("installing", step, version)
        old_skel = _snapshot_skel(work)
        rollback = Rollback(path(ROLLBACK))
        if as_packages:
            keep_for_packages(rollback, plan)
            for rel in leftovers:
                rollback.keep(path("/" + rel))
        else:
            for t in trees:
                rollback.keep(path("/" + t))
            for f in files:
                rollback.keep(path("/" + f))
        rollback.keep(runtime / "version.json")
        for entry, home in _accounts():
            conf = home / ".config"
            rollback.keep(conf / "quickshell/golden-gate")
            for rel in MANAGED + themes:
                rollback.keep(conf / rel)
                rollback.keep(conf / (rel + ".golden-gate-new"))
            for rel in RETIRED:
                rollback.keep(conf / rel)
        overlay = tree / "distro/archiso/overlay"
        for f in sorted(overlay.rglob("*")):
            rel = f.relative_to(overlay).as_posix()
            if not f.is_dir() and not rel.startswith(LIVE_ONLY):
                rollback.keep(path("/" + rel))
        rollback.keep(path("/etc/pacman.conf"))          # hold_hyprland's IgnorePkg
        for plugin in ("hyprglass.so", "hyprglass.so.hyprland", "hyprbars.so", "hyprbars.so.hyprland"):
            rollback.keep(path("/usr/lib/golden-gate/" + plugin))
        for image in sorted(path("/boot").glob("initramfs-*.img")) if path("/boot").is_dir() else []:
            rollback.keep(image)

        step = "installing CitronOS's files"
        _journal("installing", step, version)
        if as_packages:
            install_built(plan)
            match_folder_modes(rollback)
            remove_leftovers(leftovers)
        else:
            _activate(stage, trees, files)

        step = "updating your settings"
        _journal("installing", step, version)
        emit("progress", progress=0.96, message="Updating your settings…", remaining=-1)
        kept = refresh_accounts(old_skel, as_packages)

        step = "installing system files"
        _journal("installing", step, version)
        apply_overlay(tree)

        try:
            hold_hyprland(tree, emit)
        except (OSError, urllib.error.URLError, subprocess.SubprocessError) as exc:
            emit("notice", message=f"Hyprland {hyprland_release()} is installed, and the version CitronOS's desktop "
                                   f"is made for couldn't be put back ({str(exc)[:120]}). The desktop won't start "
                                   "with it after you log out: run Software Update again before then.")
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


def install_local(source: str | None = None, root: str | None = None, unsigned: bool = False) -> int:
    """As root: install CitronOS from a tree or bundle, onto this system or
    onto one mounted at `root`. A bundle file must be a signed release (its
    NAME.manifest.json and .sig beside it) unless `unsigned`: a checkout, or
    the ISO's own source, which comes from the boot medium itself."""
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
        signed = None
        if src.is_file() and not unsigned:
            base = src.name[:-len(".tar.gz")] if src.name.endswith(".tar.gz") else src.stem
            manifest, sig = src.with_name(base + ".manifest.json"), src.with_name(base + ".manifest.json.sig")
            if not (manifest.is_file() and sig.is_file()):
                print(f"! {src.name} isn't a signed CitronOS release: {manifest.name} and {sig.name} "
                      "should be beside it. (A bundle you made yourself: add --unsigned.)")
                return 2
            mine = ""
            try:
                mine = json.loads(path("/usr/share/golden-gate/version.json").read_text()).get("version", "")
            except (OSError, ValueError, AttributeError):
                pass
            signed = check_bundle(src, manifest.read_bytes(), sig.read_bytes(), mine, channel="dev")
        tree = unpack(src, work / "src") if src.is_file() else src
        if not (tree / "scripts/install.sh").exists():
            print(f"! {src} doesn't contain CitronOS.")
            return 2
        version = _tree_version(tree)
        if signed:
            version.update(version=signed["version"], tag=signed.get("tag", ""), channel=signed.get("channel", "stable"))
        where = f"onto {ROOT}" if ROOT != Path("/") else "on this computer"
        print(f"› Installing CitronOS {str(version.get('commit', ''))[:7] or '(unknown version)'} {where}…", flush=True)
        ok = install_tree(tree, version, _say, work)
    except (GitHubError, UpdateRefused, tarfile.TarError, OSError) as e:
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
        # The ISO's own source: as trusted as the medium this computer booted.
        return install_local("/usr/share/golden-gate/source.tar.gz", mnt, unsigned=True)
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
    local.add_argument("--unsigned", action="store_true",
                       help="install a bundle that isn't a signed release (one you made yourself)")
    sub.add_parser("update-disk", help="from the live ISO: update the CitronOS on this computer's disk")
    args = parser.parse_args()
    raise SystemExit(install_local(args.source, args.root, args.unsigned) if args.command == "install-local" else update_disk())
