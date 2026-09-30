#!/usr/bin/env python3
"""Keep Golden Gate application controls centralized in apps/lib."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
lib = root / "apps/lib"
standard = {
    "AppWindow.qml", "Button.qml", "Checkbox.qml", "FocusRing.qml", "Glass.qml",
    "PopUpButton.qml", "PopupMenu.qml", "RoundedImage.qml", "Segmented.qml",
    "Slider.qml", "Spring.qml", "SpringValue.qml", "Switch.qml", "Symbol.qml",
    "TextField.qml", "ToolbarButton.qml", "ToolbarPill.qml", "TrafficLights.qml",
}
errors = []
for name in sorted(standard):
    if not (lib / name).is_file():
        errors.append(f"shared component missing: apps/lib/{name}")

for path in (root / "apps").rglob("*.qml"):
    if lib in path.parents:
        continue
    if path.name in standard:
        errors.append(f"forked standard control outside shared store: {path.relative_to(root)}")

install = (root / "scripts/install.sh").read_text(encoding="utf-8")
for needle in [
    'cp -a "$REPO/apps/lib" "$SHARE/ui"',
    'ln -s ../ui "$SHARE/apps/lib"',
    'cp -a "$REPO/apps/lib" "$DATA/golden-gate/ui"',
    'ln -s ../ui "$DATA/golden-gate/apps/lib"',
]:
    if needle not in install:
        errors.append(f"installer no longer guarantees canonical shared UI: {needle}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("Shared UI architecture: one canonical application component store")
