#!/usr/bin/env bash
# Boot the ISO in QEMU and check that the desktop comes up.
#
#   distro/archiso/boot-test.sh ISO [DISPLAY] [OUTDIR]
#
# DISPLAY  std     plain VGA, no 3D (like QEMU on Windows or macOS)
#          virtio  virtio-gpu without 3D
#          virgl   virtio-gpu with 3D (needs a GL-capable host; runs under Xvfb if no $DISPLAY)
#          tcg     plain VGA, no hardware virtualisation and QEMU's default CPU model
#                  (QEMU on Windows or macOS without WHPX/HVF): slow, but must still work
#
# There is no VirtualBox (VMSVGA/vmwgfx) variant: QEMU's -vga vmware is the old
# VMware SVGA II, which today's vmwgfx refuses (probe error -38), so it would test
# a machine with no display driver at all rather than VirtualBox.
#
# The ISO's own kernel is booted directly so the console can go to a serial log,
# with the journal forwarded to it: gg-session, Hyprland's log on failure, and
# Quickshell all land in OUTDIR/serial.log. OUTDIR/screen.png is the screen once
# the session has started (or failed). Exits 0 only if the session started.
# Needs: qemu-system-x86, xorriso, socat, ImageMagick (and xvfb for virgl without a display).
set -euo pipefail

ISO="$(realpath "$1")"
VARIANT="${2:-std}"
OUT="${3:-boot-test-$VARIANT}"
TIMEOUT="${TIMEOUT:-420}"      # seconds to wait for the session
SETTLE="${SETTLE:-40}"         # seconds to let the shell draw before the screenshot
mkdir -p "$OUT"; OUT="$(realpath "$OUT")"
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- kernel + cmdline from the ISO
work="$(mktemp -d)"
extract() { xorriso -osirrox on -indev "$ISO" -extract "$1" "$2" >/dev/null 2>&1; }
extract /arch/boot/x86_64/vmlinuz-linux "$work/vmlinuz"
extract /arch/boot/x86_64/initramfs-linux.img "$work/initramfs.img"
extract /boot/syslinux "$work/syslinux" || true
extract /loader "$work/loader" || true
cmdline="$(grep -rhoE 'archisobasedir=[^ ]+ archisosearchuuid=[^ ]+' "$work/syslinux" "$work/loader" 2>/dev/null | head -n 1 || true)"
[[ -s $work/vmlinuz && -s $work/initramfs.img ]] || { echo "no kernel/initramfs under /arch/boot/x86_64 in $ISO"; exit 1; }
[[ -n $cmdline ]] || { echo "could not find the archiso kernel parameters in $ISO"; exit 1; }
cmdline+=" console=tty0 console=ttyS0,115200 systemd.journald.forward_to_console=1 gg.nosetup"   # the desktop, not Setup Assistant
# The std run also shows the boot screen (Plymouth) and captures it as boot-screen.png.
[[ $VARIANT == std ]] && cmdline+=" splash vt.global_cursor_default=0"
say "kernel parameters: $cmdline"

# ---------------------------------------------------------------- QEMU
accel=(-accel tcg); [[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)
case "$VARIANT" in
  std)    display=(-vga std -display none) ;;
  virtio) display=(-vga none -device virtio-vga -display none) ;;
  virgl)  display=(-vga none -device virtio-vga-gl -display gtk,gl=on) ;;
  tcg)    display=(-vga std -display none); accel=(-accel tcg -cpu qemu64)
          TIMEOUT="${TIMEOUT_TCG:-1800}"; SETTLE="${SETTLE_TCG:-120}" ;;
  *) echo "unknown display: $VARIANT"; exit 1 ;;
esac
wrap=(); [[ $VARIANT == virgl && -z ${DISPLAY:-} ]] && wrap=(xvfb-run -a -s "-screen 0 1920x1200x24")
rm -f "$OUT/serial.log" "$OUT/mon.sock"
say "booting ($VARIANT, ${accel[*]})"
"${wrap[@]}" qemu-system-x86_64 "${accel[@]}" -smp 4 -m 6G -no-reboot \
  -cdrom "$ISO" -kernel "$work/vmlinuz" -initrd "$work/initramfs.img" -append "$cmdline" \
  "${display[@]}" -serial "file:$OUT/serial.log" -monitor "unix:$OUT/mon.sock,server,nowait" &
qemu=$!
# Cleanup must not change the result: keep the exit status, ignore its own failures
# (QEMU is usually gone already; files from the ISO keep their read-only modes).
cleanup() { local status=$?; set +e; kill "$qemu" 2>/dev/null; chmod -R u+w "$work"; rm -rf "$work"; exit "$status"; }
trap cleanup EXIT
monitor() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon.sock" >/dev/null; }

# ---------------------------------------------------------------- wait for the session
result=timeout
for ((t = 0; t < TIMEOUT; t += 5)); do
  sleep 5
  if [[ $VARIANT == std && $t == 5 ]]; then
    monitor "screendump $OUT/boot-screen.ppm" && sleep 1
    [[ -f $OUT/boot-screen.ppm ]] && convert "$OUT/boot-screen.ppm" "$OUT/boot-screen.png" && rm -f "$OUT/boot-screen.ppm"
  fi
  if grep -q 'session started' "$OUT/serial.log" 2>/dev/null; then result=started; break; fi
  if grep -q 'gg-session.*Hyprland exited' "$OUT/serial.log" 2>/dev/null; then result=exited; break; fi
  kill -0 "$qemu" 2>/dev/null || { result=qemu-exited; break; }
done
say "result: $result after ${t}s"

# Hyprland is up; the desktop (wallpaper, menu bar, Dock) appears once the shell
# has loaded. Without it the screen is just the background colour and a cursor.
if [[ $result == started ]]; then
  result=no-shell
  for ((; t < TIMEOUT; t += 5)); do
    if grep -aq 'quickshell.*Configuration Loaded' "$OUT/serial.log" 2>/dev/null; then result=started; break; fi
    kill -0 "$qemu" 2>/dev/null || { result=qemu-exited; break; }
    sleep 5
  done
  say "shell: $( [[ $result == started ]] && echo "loaded after ${t}s" || echo "$result after ${t}s")"
fi

if kill -0 "$qemu" 2>/dev/null; then
  sleep "$SETTLE"
  monitor "screendump $OUT/screen.ppm" && sleep 2
  [[ -f $OUT/screen.ppm ]] && convert "$OUT/screen.ppm" "$OUT/screen.png" && rm "$OUT/screen.ppm"
  monitor quit || true
fi
wait "$qemu" 2>/dev/null || true

# ---------------------------------------------------------------- report
say "session log"
grep -aE 'gg-session|golden-gate|hyprland-log|hyprland-config|quickshell|Hyprland|Failed|failed|segfault|core dump' "$OUT/serial.log" | tail -n 150 || true
if [[ -f $OUT/screen.png ]]; then
  # A small copy in the job log, so the screen can be checked from the log alone.
  convert "$OUT/screen.png" -resize 960x -quality 70 "$OUT/screen-small.jpg"
  echo "--- screen-small.jpg base64 begin ---"; base64 -w0 "$OUT/screen-small.jpg"; echo; echo "--- end ---"
fi
# A session that starts with config errors (shown as a red banner) still fails.
if grep -aq 'hyprland-config\[' "$OUT/serial.log" 2>/dev/null; then
  say "Hyprland reported config errors:"; grep -a 'hyprland-config\[' "$OUT/serial.log"
  result=config-errors
fi
[[ $result == started ]]
