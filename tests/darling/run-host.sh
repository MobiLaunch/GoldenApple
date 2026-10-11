#!/usr/bin/env bash
# Execute Darling's patched Objective-C source with GNUstep Foundation.
# This checks controller behavior, not a complete Darwin runtime or display.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
source_tree=${1:?Usage: run-host.sh /path/to/patched/darling}
coco="$source_tree/src/external/cocotron"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
read -r -a flags <<< "$(gnustep-config --objc-flags)"
read -r -a libs <<< "$(gnustep-config --base-libs)"
"${CC:-clang}" "${flags[@]}" -I"$(gcc -print-file-name=include)" \
  -I"$here/host" -I"$coco/AppKit/include" \
  -include Foundation/Foundation.h \
  "$coco/AppKit/NSViewController.m" "$coco/AppKit/NSLayoutConstraint.m" \
  "$here/controller.m" -o "$temp/controller" "${libs[@]}"
"$temp/controller"
