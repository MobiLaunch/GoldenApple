#!/usr/bin/env python3
"""Guard Settings controls against becoming decorative/no-op UI."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
panes = root / "apps" / "settings" / "panes"
errors = []

control_re = re.compile(r"\b(?:Switch|Slider|Button|PopUpButton|Segmented|TextField)\s*\{")
handler_re = re.compile(r"\b(?:onToggled|onMoved|onClicked|onPicked|onAccepted|onTextChanged)\s*:")

for path in sorted(panes.glob("*.qml")):
    text = path.read_text(encoding="utf-8")
    controls = len(control_re.findall(text))
    handlers = len(handler_re.findall(text))
    if controls and handlers < controls:
        errors.append(f"{path.name}: {controls} adjustable controls but only {handlers} action handlers")

required = {
    "AccessibilityPane.qml": ['setPref(["reduceMotion"]', 'setPref(["reduceTransparency"]', "text-scaling-factor", 'setRecord("accessibility"'],
    "AppearancePane.qml": ['setPref(["glass"]', "accent-color", "overlay-scrolling"],
    "BatteryPane.qml": ["powerprofilesctl"],
    "BluetoothPane.qml": ["bluetoothctl"],
    "DateTimePane.qml": ["timedatectl"],
    "DisplaysPane.qml": ['setPref(["display", "brightness"]', 'setPref(["display", "nightShift"]', 'setPref(["display", "warmth"]'],
    "DockPane.qml": ['setDock("size"', 'setDock("animateLaunch"', 'setDock("indicators"'],
    "FocusPane.qml": ['sys.run(["gg-pref", "focus." + key', 'sys.prefs = sys.setIn(sys.prefs, ["focus"]', 'FocusState { id: status', 'function setSchedule('],
    "KeyboardPane.qml": ["setInput("],
    "PrivacyPane.qml": ["setPrivacy("],
    "SoundPane.qml": ["wpctl"],
    "TrackpadPane.qml": ["setInput("],
    "UpdatePane.qml": ["update-helper.py", "ProgressBar", "etaText"],
    "UsersPane.qml": ["passwd"],
    "WallpaperPane.qml": ['setPref(["wallpaper"]'],
    "LanguagePane.qml": ["localectl", "set-locale", "PopUpButton"],
    "WifiPane.qml": ["nmcli"],
}
for name, needles in required.items():
    text = (panes / name).read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            errors.append(f"{name}: missing system/persistence wiring {needle!r}")


language = (panes / "LanguagePane.qml").read_text(encoding="utf-8")
if "sudo localectl" in language:
    errors.append("LanguagePane.qml: reintroduced terminal/manual locale instructions")

appearance = (panes / "AppearancePane.qml").read_text(encoding="utf-8")
for needle in ["setMode(", "appearance.json", "accent-color", "overlay-scrolling", 'setPref(["glass"]']:
    if needle not in appearance:
        errors.append(f"AppearancePane.qml: missing real appearance wiring {needle!r}")

sys_qml = (root / "apps/settings/Sys.qml").read_text(encoding="utf-8")
for needle in ["gg-pref", "set-prefs.py", "recordSave", "hyprctl", "gg-hyprglass-sync"]:
    if needle not in sys_qml:
        errors.append(f"Sys.qml: missing central settings plumbing {needle!r}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("Settings wiring: adjustable controls have backing actions and persistent state")
