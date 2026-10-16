#!/usr/bin/env bash
# Compile the patch's actual PIP implementation against Apple's AppKit; build
# an Intel fixture that will load Darling's installed PIP unchanged on Linux.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
[[ $(uname -s) == Darwin ]] || { echo 'PIP native tests require macOS and Xcode command-line tools.' >&2; exit 1; }
out=${1:?Usage: build-pip-tests.sh /output/directory [--build-only]}
mkdir -p "$out"
out=$(cd -- "$out" && pwd)
source_dir=$(mktemp -d)
trap 'rm -rf "$source_dir"' EXIT
python3 - "$root" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1]) / 'third_party/darling'
lock = json.loads((root / 'source.lock.json').read_text())
patch = next(p for p in lock['patches'] if p['path'] == 'patches/0003-pip-framework.patch')
if hashlib.sha256((root / patch['path']).read_bytes()).hexdigest() != patch['sha256']:
    raise SystemExit('PIP patch checksum mismatch')
PY
# Only extract newly added framework files, without mutating any source tree.
git -C "$source_dir" apply --include='src/private-frameworks/PIP/*' \
  "$root/third_party/darling/patches/0003-pip-framework.patch"
pip_source="$source_dir/src/private-frameworks/PIP"
framework="$out/frameworks/PIP.framework"
mkdir -p "$framework/Versions/A" "$out/native" "$out/PIPLab.app/Contents/MacOS"
ln -sfn A "$framework/Versions/Current"
ln -sfn Versions/Current/PIP "$framework/PIP"
install_name=/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP
for architecture in x86_64 arm64; do
  minimum=11.0
  [[ $architecture != x86_64 ]] || minimum=10.13
  xcrun clang -arch "$architecture" -mmacosx-version-min="$minimum" -fobjc-arc -fblocks \
    -I"$pip_source/include" -dynamiclib "$pip_source/src/PIP.m" -framework Cocoa \
    -install_name "$install_name" -compatibility_version 1.0 -current_version 1.0 \
    -o "$out/native/PIP-$architecture"
done
lipo -create "$out/native/PIP-x86_64" "$out/native/PIP-arm64" -output "$framework/Versions/A/PIP"
for architecture in "$(uname -m)" x86_64; do
  binary="$out/native/PIPLab-$architecture"
  minimum=11.0
  [[ $architecture != x86_64 ]] || minimum=10.13
  xcrun clang -arch "$architecture" -mmacosx-version-min="$minimum" -fobjc-arc -fblocks \
    -I"$pip_source/include" "$root/tests/darling/pip.m" "$framework/Versions/A/PIP" \
    -framework Cocoa -o "$binary"
done
cp "$out/native/PIPLab-x86_64" "$out/PIPLab.app/Contents/MacOS/PIPLab"
cat > "$out/PIPLab.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PIPLab</string>
<key>CFBundleIdentifier</key><string>org.goldengate.DarlingPIPLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>10.13</string>
</dict></plist>
EOF
lipo "$out/PIPLab.app/Contents/MacOS/PIPLab" -verify_arch x86_64
otool -L "$out/PIPLab.app/Contents/MacOS/PIPLab" | grep -F "$install_name"
cp "$root/third_party/darling/source.lock.json" "$out/source.lock.json"
ditto -c -k --keepParent "$out/PIPLab.app" "$out/PIPLab.zip"
if [[ ${2:-} != --build-only ]]; then
  DYLD_FRAMEWORK_PATH="$out/frameworks" "$out/native/PIPLab-$(uname -m)" "$out/native-results.json"
fi
