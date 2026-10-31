#!/usr/bin/env bash
# Build a distributable Intel Mach-O fixture using Apple's macOS SDK.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $(uname -s) == Darwin ]] || { echo 'Build this fixture on macOS with Xcode command-line tools.' >&2; exit 1; }
app=${1:?Usage: build-fixture.sh /output/ControllerLab.app}
mkdir -p "$app/Contents/MacOS"
xcrun clang -arch x86_64 -mmacosx-version-min=10.10 -fno-objc-arc \
  "$here/fixtures/ControllerLab.m" -framework Cocoa -o "$app/Contents/MacOS/ControllerLab"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ControllerLab</string>
<key>CFBundleIdentifier</key><string>org.goldengate.DarlingControllerLab</string>
<key>CFBundleName</key><string>Darling Controller Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>10.10</string>
</dict></plist>
EOF
echo "Built $app"
