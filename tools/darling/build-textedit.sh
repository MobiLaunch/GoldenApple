#!/usr/bin/env bash
# Build Darling's open-source TextEdit as an unchanged Intel Mac app with
# Apple's macOS SDK. The source revision is the TextEdit submodule recorded by
# the locked Darling commit, so it changes only when source.lock.json does.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
[[ $(uname -s) == Darwin ]] || { echo 'Build TextEdit on macOS with Xcode command-line tools.' >&2; exit 1; }
app=${1:?Usage: build-textedit.sh /output/TextEdit.app}
[[ ! -e $app ]] || { echo "Refusing to replace existing $app" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

darling=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["darling_commit"])' \
  "$root/third_party/darling/source.lock.json")
git -C "$work" init -q darling
git -C "$work/darling" fetch -q --depth 1 --filter=blob:none https://github.com/darlinghq/darling.git "$darling"
read -r mode type commit _ < <(git -C "$work/darling" ls-tree FETCH_HEAD src/external/TextEdit)
[[ $mode == 160000 && $type == commit ]] || { echo 'Locked Darling has no TextEdit submodule' >&2; exit 1; }
git clone -q https://github.com/darlinghq/darling-TextEdit.git "$work/TextEdit"
git -C "$work/TextEdit" checkout -q --detach "$commit"
src=$work/TextEdit
[[ $(git -C "$src" rev-parse HEAD) == "$commit" ]]

contents=$app/Contents
resources=$contents/Resources
mkdir -p "$contents/MacOS" "$resources"
sources=(Document.m Controller.m ScalingScrollView.m MultiplePageView.m Preferences.m Edit_main.m
  EncodingManager.m DocumentController.m DocumentWindowController.m LinePanelController.m
  PrintPanelAccessoryController.m DocumentPropertiesPanelController.m FontNameTransformer.m
  PrintingTextView.m)
# The upstream project is manual retain/release and links only Cocoa.
(cd "$src" && xcrun clang -arch x86_64 -mmacosx-version-min=10.10 -fno-objc-arc -std=gnu99 \
  -Wno-deprecated-declarations -Wno-objc-method-access "${sources[@]}" \
  -framework Cocoa -o "$contents/MacOS/TextEdit")

version=$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$src/Version.xcconfig")
sed "s/\$(CURRENT_PROJECT_VERSION)/$version/" "$src/Info-TextEdit.plist" > "$contents/Info.plist"
plutil -lint "$contents/Info.plist" >/dev/null
printf 'APPL????' > "$contents/PkgInfo"
# Compiled nibs ship in the source (keyedobjects.nib); no Interface Builder step.
cp -R "$src/Base.lproj" "$src/English.lproj" "$src/DocumentWindow.nib" \
  "$src/TextEdit.scriptSuite" "$src/TextEdit.scriptTerminology" \
  "$src/TextEdit Test Document.rtf" "$resources/"
for icon in Edit html rtf rtfd txt; do
  iconutil -c icns "$src/$icon.iconset" -o "$resources/$icon.icns"
done
printf '%s\n' "$commit" > "$resources/GoldenGateSourceRevision"
echo "Built $app from darling-TextEdit $commit"
