#!/usr/bin/env python3
"""Mac app support's setup (apps/software/darling-setup.sh), run for real
against stand-ins for sudo, pacman, pacman-key, git, makepkg and darling:

- it installs darling-bin (Darling's prebuilt release), never darling-git or
  darling, whose dependencies aren't installable on Arch;
- it refreshes the package signing keys and updates the system before
  installing, and rebuilds the keyring when pacman can't verify packages;
- it falls back to the AUR's GitHub mirror when the AUR doesn't answer;
- a failure says what went wrong and where the log is.
"""
from __future__ import annotations

from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "apps/software/darling-setup.sh"
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


FAKES = {
    "sudo": 'echo "sudo $*" >> "$CALLS"; [ "$1" = -v ] && exit 0; exec "$@"',
    # pacman: the keyring refresh fails with a signature error the first time
    # when FAIL_KEYRING is set; everything else succeeds.
    "pacman": '''echo "pacman $*" >> "$CALLS"
case "$*" in
  *archlinux-keyring*) if [ -n "$FAIL_KEYRING" ] && [ ! -e "$STATE/keyring-fixed" ]; then
        echo "error: archlinux-keyring: signature from \\"Arch\\" is unknown trust"; exit 1; fi ;;
esac
exit 0''',
    "pacman-key": 'echo "pacman-key $*" >> "$CALLS"; [ "$1" = --populate ] && touch "$STATE/keyring-fixed"; exit 0',
    "pgrep": "exit 1",
    # git: the AUR fails when AUR_DOWN is set; a clone makes a PKGBUILD.
    "git": '''echo "git $*" >> "$CALLS"
for last; do :; done
case "$*" in *aur.archlinux.org*) [ -n "$AUR_DOWN" ] && exit 128 ;; esac
mkdir -p "$last" && echo "pkgname=darling-bin" > "$last/PKGBUILD"''',
    "makepkg": """echo "makepkg $* in $(basename "$PWD")" >> "$CALLS"
cat > "$STATE/bin/darling" <<'EOF'
#!/bin/sh
echo "darling $*" >> "$CALLS"
EOF
chmod +x "$STATE/bin/darling"
""",
}


def setup(tmp: Path, **env: str):
    fakes = tmp / "fakes"
    (tmp / "state/bin").mkdir(parents=True, exist_ok=True)
    fakes.mkdir(exist_ok=True)
    for name, body in FAKES.items():
        (fakes / name).write_text("#!/bin/sh\n" + body + "\n")
        (fakes / name).chmod(0o755)
    calls = tmp / "calls"
    calls.write_text("")
    e = {**os.environ, "PATH": f"{tmp/'state/bin'}:{fakes}:/usr/bin:/bin", "HOME": str(tmp / "home"),
         "XDG_CACHE_HOME": str(tmp / "cache"), "CALLS": str(calls), "STATE": str(tmp / "state"), **env}
    p = subprocess.run(["bash", str(SCRIPT)], input="y\n\n", env=e, capture_output=True, text=True, timeout=60)
    return p, calls.read_text().splitlines()


with tempfile.TemporaryDirectory() as t:
    p, calls = setup(Path(t))
    check(p.returncode == 0, f"setup succeeds: {p.stdout[-400:]}{p.stderr[-200:]}")
    joined = "\n".join(calls)
    check("git clone --depth 1 https://aur.archlinux.org/darling-bin.git darling-bin" in joined, f"darling-bin from the AUR: {calls}")
    check("darling-git" not in joined and "aur.archlinux.org/darling.git" not in joined, "never the source builds")
    check(any(c.startswith("makepkg --syncdeps --install") and c.endswith("in darling-bin") for c in calls), f"makepkg installs it: {calls}")
    order = [next((i for i, c in enumerate(calls) if needle in c), 99) for needle in
             ("pacman -Sy --needed --noconfirm archlinux-keyring", "pacman -Su --noconfirm", "pacman -S --needed --noconfirm base-devel git", "makepkg")]
    check(order == sorted(order) and 99 not in order, f"keys, then a system update, then the tools, then Darling: {calls}")
    check(not any("multilib" in c or "lib32" in c for c in calls), "no 32-bit packages needed")
    check("darling shell true" in joined, "the Mac environment is set up at the end")
    check("Mac app support is ready" in p.stdout, "it says it's ready")
    check((Path(t) / "cache/golden-gate/darling-setup.log").exists(), "a log is kept")

with tempfile.TemporaryDirectory() as t:
    p, calls = setup(Path(t), FAIL_KEYRING="1", AUR_DOWN="1")
    check(p.returncode == 0, f"recovers from bad keys and a down AUR: {p.stdout[-400:]}")
    check("pacman-key --init" in calls and "pacman-key --populate archlinux" in calls, f"the keyring is rebuilt: {calls}")
    check(any("github.com/archlinux/aur.git" in c and "--branch darling-bin" in c for c in calls), f"the GitHub mirror is used: {calls}")

with tempfile.TemporaryDirectory() as t:
    FAKES_SAVED = FAKES["makepkg"]
    FAKES["makepkg"] = 'echo "==> ERROR: A failure occurred in package()."; exit 4'
    p, calls = setup(Path(t))
    FAKES["makepkg"] = FAKES_SAVED
    check(p.returncode == 1, "a failed install fails")
    check("Darling couldn't be installed." in p.stdout and "darling-setup.log" in p.stdout, f"and says so, with the log: {p.stdout[-300:]}")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Darling setup: installs darling-bin after readying pacman; repairs keys; uses the AUR mirror; reports failures")
