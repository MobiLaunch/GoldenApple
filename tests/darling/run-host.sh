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
# Hosted images can have multiple GCC versions. Clang's selected GCC may lack
# libobjc, while GNUstep's installed Objective-C runtime belongs to another.
objc_library=$(gcc -print-file-name=libobjc.so)
if [[ ! -f $objc_library ]]; then
  for candidate in /usr/lib/gcc/*/*/libobjc.so; do
    if [[ -f $candidate ]]; then objc_library=$candidate; break; fi
  done
fi
[[ -f $objc_library ]] || { echo 'Objective-C runtime development library is missing.' >&2; exit 1; }
"${CC:-clang}" "${flags[@]}" -I"$(gcc -print-file-name=include)" \
  -I"$(dirname -- "$objc_library")/include" -L"$(dirname -- "$objc_library")" \
  -I"$here/host" -I"$coco/AppKit/include" \
  -include Foundation/Foundation.h \
  "$coco/AppKit/NSViewController.m" "$coco/AppKit/NSLayoutConstraint.m" \
  "$here/controller.m" -o "$temp/controller" "${libs[@]}"
"$temp/controller"
