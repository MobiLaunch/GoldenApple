#!/usr/bin/env bash
# Build CitronOS's packages and install them on a clean Arch system (T-2.1).
# Run as root in an archlinux container, from the repository:
#
#   docker run --rm -v "$PWD:/repo" -w /repo archlinux:latest packaging/check.sh [OUTDIR]
#
# Then: `pacman -Qkk` finds every packaged file as packaged, a new account
# gets no shell of its own (~/.config/quickshell) and Quickshell finds the
# system's, and the account's hyprland.conf is the one-line stub.
set -euo pipefail
OUT="${1:-/repo/out/packages}"
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }
fail() { echo "::error::$*"; FAILED=$((FAILED + 1)); }
FAILED=0

sh /repo/distro/pin-archive.sh   # the packages as of distro/archive-date
for try in 1 2 3; do   # mirrors drop connections now and then
  pacman -Syuu --noconfirm --needed base-devel git nodejs librsvg >/dev/null && break
  [[ $try == 3 ]] && exit 1
  sleep $((try * 20))
done

say "building (makepkg, as an unprivileged account)"
useradd -m builder 2>/dev/null || true
work=$(mktemp -d)
# makepkg wants a writable checkout of its own; the build copies tracked files.
git config --global --add safe.directory '*'
cp -a /repo "$work/repo"
chown -R builder "$work"
su builder -c "git config --global --add safe.directory '*'; cd '$work/repo/packaging/citronos' && makepkg -d --noconfirm"
mkdir -p "$OUT"
cp "$work"/repo/packaging/citronos/*.pkg.tar.* "$OUT/"
ls -l "$OUT"

say "installing on a clean system"
# (In a container, systemd's own hooks say they can't reach systemd: not ours.)
for try in 1 2 3; do
  pacman -U --noconfirm "$OUT"/*.pkg.tar.* >/dev/null && break
  [[ $try == 3 ]] && { fail "the packages didn't install"; exit 1; }
  sleep $((try * 20))
done
pacman -Q | grep '^citronos'

say "pacman -Qkk: every packaged file as packaged"
if ! pacman -Qkk citronos-runtime citronos-shell citronos-hyprland-config citronos-theme citronos; then
  fail "pacman -Qkk found files changed since they were installed"
fi

say "a new account"
useradd -m newcomer
home=/home/newcomer
[[ ! -e $home/.config/quickshell ]] || fail "a new account has a shell of its own (~/.config/quickshell)"
[[ $(grep -v '^#' "$home/.config/hypr/hyprland.conf" | grep -c .) == 1 ]] ||
  fail "the new account's hyprland.conf isn't the one-line stub"
grep -qx "source = /usr/share/golden-gate/hypr/hyprland.conf" "$home/.config/hypr/hyprland.conf" ||
  fail "the stub doesn't source the packaged settings"
# What `qs -c golden-gate` finds, for that account: with nothing running,
# Quickshell names the config it looked for ("No running instances for …").
found=$(su newcomer -c 'XDG_RUNTIME_DIR=$(mktemp -d) timeout 5 qs -c golden-gate ipc show 2>&1' || true)
echo "$found" | sed 's/^/  /' | head -n 5
if ! echo "$found" | grep -q "/etc/xdg/quickshell/golden-gate/shell.qml"; then
  fail "Quickshell doesn't find the system's shell for a new account"
fi
[[ -f /etc/xdg/quickshell/golden-gate/shell.qml && -f /etc/xdg/quickshell/golden-gate/lock-shell.qml ]] ||
  fail "the shell isn't in /etc/xdg/quickshell/golden-gate"
[[ $(readlink /etc/xdg/quickshell/golden-gate/ui) == /usr/share/golden-gate/ui && -f /usr/share/golden-gate/ui/theme/Release.qml ]] ||
  fail "the shell's ui/ isn't the shared UI"
# A stand-in qs that says what it was asked to run (there's no display here).
install -d /tmp/stand-in && printf '#!/bin/sh\necho "$@"\n' > /tmp/stand-in/qs && chmod 755 /tmp/stand-in/qs
lock=$(su newcomer -c 'PATH=/tmp/stand-in:$PATH gg-lock serve' | sed -n 's/^-p //p')
[[ $lock == /etc/xdg/quickshell/golden-gate/lock-shell.qml ]] || fail "gg-lock serve runs '$lock', not the system's lock screen"

say "every gg-* command runs something that's there"
for w in /usr/bin/gg-*; do
  target=$(sed -n 's/^exec .* \(\/usr\/[^ ]*\) "\$@"$/\1/p' "$w")
  [[ -z $target || -e $target ]] || fail "$w runs $target, which isn't installed"
done
for f in /usr/share/dbus-1/services/org.citronos.*.service; do
  exec=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$f")
  [[ -x $exec ]] || fail "$f starts $exec, which isn't installed"
done

if (( FAILED )); then echo "$FAILED problem(s)"; exit 1; fi
say "the packages install cleanly"
