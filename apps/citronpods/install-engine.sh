#!/bin/bash
# Opt-in first-party build of the Qt6-fixed CitronPods M10 source archive.
# Installs ONLY the persistent backend, not its duplicate standalone GUI.
# The user supplies their existing LibrePods-CitronPods-M10-Qt6-Fixed.zip.
set -euo pipefail
archive="${1:-}"
if [[ ! -f "$archive" ]]; then
  echo "Usage: gg-install-citronpods ~/Downloads/LibrePods-CitronPods-M10-Qt6-Fixed.zip" >&2
  exit 2
fi
for executable in cmake ninja python3 c++; do
  command -v "$executable" >/dev/null || {
    echo "Missing build tool: $executable" >&2
    echo "On Arch, install build dependencies with: sudo pacman -S --needed base-devel cmake ninja qt6-base qt6-declarative qt6-connectivity libpulse" >&2
    exit 2
  }
done
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gg-citronpods.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
python3 - "$archive" "$tmp/source" <<'PY'
import os, pathlib, stat, sys, zipfile
archive, target = sys.argv[1:]
target = pathlib.Path(target)
total = 0
with zipfile.ZipFile(archive) as src:
    root = [name[:-len("citronos/CMakeLists.txt")] for name in src.namelist()
            if name.endswith("citronos/CMakeLists.txt")]
    if len(root) != 1:
        raise SystemExit("Not a compatible CitronPods source archive")
    root = root[0]
    # The upstream ZIP also contains multi-megabyte app fonts and unrelated
    # demo assets. Import only the Qt daemon sources and the exact LibrePods
    # parser headers it includes. Never bundle the separate Qt GUI's fonts.
    linux_headers = {
        "linux/battery.hpp", "linux/airpods_packets.h",
        "linux/logger.h", "linux/enums.h", "linux/BasicControlCommand.hpp"
    }
    names = [m for m in src.infolist() if m.filename.startswith(root) and not m.is_dir()
             and (m.filename[len(root):].startswith("citronos/")
                  or m.filename[len(root):] in linux_headers)]
    if len(names) > 200:
        raise SystemExit("Unexpected CitronPods archive contents")
    for entry in names:
        rel = entry.filename[len(root):]
        parts = pathlib.PurePosixPath(rel).parts
        if not parts or any(part in ("", ".", "..") for part in parts):
            raise SystemExit("Unsafe path in CitronPods archive")
        if stat.S_ISLNK(entry.external_attr >> 16) or not stat.S_ISREG(entry.external_attr >> 16):
            # Some ZIP creators mark ordinary files as mode=0. Those are safe.
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise SystemExit("Linked files are not allowed")
        if entry.file_size > 2_000_000:
            raise SystemExit("Oversized source member")
        total += entry.file_size
        if total > 13_000_000:
            raise SystemExit("Source archive exceeds limits")
        dest = target.joinpath(*parts)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with src.open(entry) as read, dest.open("wb") as write:
            while chunk := read.read(1024*128):
                write.write(chunk)
needed = ["citronos/CMakeLists.txt", "citronos/src/daemonmain.cpp",
          "citronos/src/ProtocolBridge.cpp", "citronos/src/PodManager.cpp",
          "linux/battery.hpp", "linux/airpods_packets.h"]
if not all((target / name).is_file() for name in needed):
    raise SystemExit("Missing expected M10 source files")
# Qt6.7+ enum scoping: M10 Qt6 Fixed already correct, but refuse the old
# archive's unscoped references that fail to compile.
bridge = (target/"citronos/src/ProtocolBridge.cpp").read_text()
if "QBluetoothSocket::UnconnectedState" in bridge or "QBluetoothSocket::ConnectedState" in bridge:
    raise SystemExit("This source has the old Qt Bluetooth enum error. Use M10-Qt6-Fixed.zip")
PY
echo 'Configuring native CitronPods system engine…'
cmake -S "$tmp/source/citronos" -B "$tmp/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
echo 'Building only the daemon (the duplicate Qt app is intentionally not installed)…'
cmake --build "$tmp/build" --parallel 2 --target citronpods-daemon
install -Dm755 "$tmp/build/citronpods-daemon" "$HOME/.local/bin/citronpods-daemon"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$unit_dir"
if [[ -f "${GG_CITRONPODS_UNIT:-}" ]]; then
  install -m644 "$GG_CITRONPODS_UNIT" "$unit_dir/citronpods-daemon.service"
elif [[ -f "/usr/share/golden-gate/apps/citronpods/citronpods-daemon.service" ]]; then
  install -m644 /usr/share/golden-gate/apps/citronpods/citronpods-daemon.service "$unit_dir/citronpods-daemon.service"
else
  echo 'Could not locate the Golden Gate CitronPods service unit.' >&2
  exit 1
fi
systemctl --user daemon-reload
systemctl --user enable --now citronpods-daemon.service
echo 'CitronPods is integrated. Open Settings → AirPods or Control Center.'
