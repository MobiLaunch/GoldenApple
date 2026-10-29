#!/usr/bin/env bash
# Software Update onto CitronOS's packages (T-2.1), with the real makepkg and
# pacman: a system scripts/install.sh --system made, with two accounts, is
# updated by golden_update.py's install_tree from this repository. Run as root
# in an archlinux container, from the repository:
#
#   docker run --rm -v "$PWD:/repo" -w /repo archlinux:latest packaging/migrate-check.sh
#
# Then: the packages are installed and pacman -Qkk finds every file as
# packaged; install.sh's leftovers are gone; an unedited account runs the
# system's shell (a link until its next login) with the one-line hyprland.conf,
# an edited one keeps its own; an upgrade to a later build works the same; and
# an update that fails after pacman puts back the files and pacman's records
# (pacman -Qkk and -Dk stay clean, the earlier versions are the installed ones).
# What needs the whole image (its ~150 packages, the glass plugin's download,
# services) is left out.
set -euo pipefail
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }
fail() { echo "::error::$*"; FAILED=$((FAILED + 1)); }
FAILED=0

sh /repo/distro/pin-archive.sh
for try in 1 2 3; do
  # Hyprland and Quickshell as a CitronOS system has them (install.sh's
  # pacman.conf holds Hyprland, so it can't come in as a dependency later).
  pacman -Syuu --noconfirm --needed base-devel git nodejs librsvg python hyprland quickshell >/dev/null && break
  [[ $try == 3 ]] && exit 1
  sleep $((try * 20))
done
git config --global --add safe.directory '*'
tree=$(mktemp -d)
git -C /repo ls-files -z | (cd /repo && tar --null -T - -cf -) | tar -xf - -C "$tree"
commit=$(git -C /repo rev-parse HEAD)
date=$(git -C /repo log -1 --format=%cI)

say "a system scripts/install.sh made"
GG_SKIP_BUILD=1 bash "$tree/scripts/install.sh" --system / >/dev/null
useradd -m ada
useradd -m bob
echo "bind = SUPER, B, exec, firefox" >> /home/bob/.config/hypr/hyprland.conf
[[ -d /home/ada/.config/quickshell/golden-gate && -e /usr/local/bin/gg-settings ]] || { fail "install.sh didn't make the old layout"; exit 1; }

# install_tree, as Software Update runs it, without what needs the whole image.
update() { # update DATE [fail]
  python3 - "$tree" "$commit" "$1" "${2:-}" <<'PY'
import importlib.util, sys
from pathlib import Path
tree, commit, date, failing = sys.argv[1:]
spec = importlib.util.spec_from_file_location("golden_update", Path(tree) / "apps/settings/golden_update.py")
gu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gu)
gu.install_packages = lambda tree, emit: {}
gu.update_hyprglass = lambda tree, emit=None: None
gu.update_hyprbars = lambda tree, emit: None
def services(tree):
    if failing:
        raise OSError("a failure after pacman, on purpose")
gu.enable_services = services
work = Path(gu.tempfile.mkdtemp(prefix="gg-golden-update-", dir="/var/tmp"))
ok = gu.install_tree(Path(tree), {"commit": commit, "date": date}, gu._say, work)
sys.exit(0 if ok else 1)
PY
}
clean() { # clean WHEN
  if ! out=$(pacman -Qkk citronos-runtime citronos-shell citronos-hyprland-config citronos-theme citronos 2>&1); then
    fail "$1: pacman -Qkk finds packaged files changed:"; echo "$out" | grep -v ' 0 altered' | head -n 20
  fi
  if ! out=$(pacman -Dk 2>&1); then fail "$1: pacman -Dk: $out"; fi
}

say "Software Update onto the packages"
update "$date" || fail "the update didn't install"
pacman -Q | grep '^citronos' || fail "no citronos packages are installed"
id citronos-build >/dev/null || fail "the account that builds CitronOS wasn't made"
clean "after the update"
for gone in /usr/local/bin/gg-settings /usr/local/bin/gg-lock /usr/share/golden-gate/runtime /etc/skel/.config/quickshell \
            /etc/skel/.config/hypr/golden-gate /etc/pacman.d/hooks/citronos-pacman.hook /etc/pacman.d/hooks/citronos-release.hook; do
  [[ ! -e $gone && ! -L $gone ]] || fail "install.sh's $gone is still there"
done
grep -q CitronOS /usr/lib/os-release || fail "os-release doesn't name CitronOS"
[[ $(readlink /home/ada/.config/quickshell/golden-gate) == /etc/xdg/quickshell/golden-gate ]] ||
  fail "Ada's shell isn't a link to the system's: $(ls -ld /home/ada/.config/quickshell/golden-gate)"
[[ $(stat -c %U /home/ada/.config/quickshell/golden-gate) == ada ]] || fail "the link isn't Ada's"
grep -qx "source = /usr/share/golden-gate/hypr/hyprland.conf" /home/ada/.config/hypr/hyprland.conf &&
  [[ $(grep -v '^#' /home/ada/.config/hypr/hyprland.conf | grep -c .) == 1 ]] || fail "Ada's hyprland.conf isn't the stub"
[[ ! -e /home/ada/.config/hypr/golden-gate/motion.conf ]] || fail "Ada keeps a copy of motion.conf her stub doesn't use"
for f in input accessibility displays windows; do
  [[ -e /home/ada/.config/hypr/golden-gate/$f.conf ]] || fail "Ada's $f.conf (hers, sourced by the stub) is gone"
done
grep -q firefox /home/bob/.config/hypr/hyprland.conf || fail "Bob's edited hyprland.conf was replaced"
[[ -e /home/bob/.config/hypr/hyprland.conf.golden-gate-new ]] || fail "Bob wasn't given the new one beside his"
[[ -e /home/bob/.config/hypr/golden-gate/motion.conf ]] || fail "Bob's hyprland.conf uses motion.conf, and it's gone"
# The next login: gg-session's part, as Ada.
block=$(sed -n '/^shell_link=/,/^fi$/p' /usr/local/bin/gg-session)
su ada -c "$block"
[[ ! -e /home/ada/.config/quickshell && ! -L /home/ada/.config/quickshell ]] || fail "gg-session left Ada's link"

say "an upgrade to a later build"
before=$(pacman -Q citronos-runtime)
update "$(date -u -d "$date + 1 day" +%Y-%m-%dT%H:%M:%SZ)" || fail "the upgrade didn't install"
after=$(pacman -Q citronos-runtime)
[[ $before != "$after" ]] || fail "citronos-runtime is still $before"
echo "  $before → $after"
clean "after the upgrade"

say "an update that fails after pacman"
update "$(date -u -d "$date + 2 days" +%Y-%m-%dT%H:%M:%SZ)" fail && fail "the failing update said it installed"
[[ $(pacman -Q citronos-runtime) == "$after" ]] || fail "pacman's records aren't the earlier ones: $(pacman -Q citronos-runtime)"
clean "after the rollback"

if (( FAILED )); then echo "$FAILED problem(s)"; exit 1; fi
say "Software Update moves an install.sh system onto the packages, upgrades them and rolls back cleanly"
