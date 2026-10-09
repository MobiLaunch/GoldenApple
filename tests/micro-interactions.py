#!/usr/bin/env python3
"""Micro-interaction contracts: shared controls, shell surface and Reduce Motion.

The offscreen native-control tests exercise actual keyboard feedback and the
segmented pill's reduced-motion snap. These source-level guards protect shell
animations that require a running Wayland compositor for visual verification.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
failures = []


def check(path, needles, description):
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [piece for piece in needles if piece not in text]
    if missing:
        failures.append(f"{description}: missing {missing!r}")
    else:
        print("ok: " + description)


check("apps/lib/Button.qml", [
    "Accessible.onPressAction: b.activate()",
    "Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) b.activate() }",
    "property bool keyboardPressed: false",
    "pressed: ma.pressed || b.keyboardPressed",
    "Timer { id: releaseFeedback; interval: 90;",
], "Liquid Glass buttons respond the same way to pointer, keyboard and accessibility")

check("apps/lib/ToolbarButton.qml", [
    "Accessible.onPressAction: button.activate()",
    "pressed: tap.pressed || button.keyboardPressed",
    "Timer { id: keyRelease; interval: 90;",
], "toolbar buttons have tactile keyboard feedback")

check("apps/lib/Segmented.qml", [
    'objectName: "segmentedSelectionPill"',
    "Behavior on x { enabled: !Theme.reduceMotion;",
    "Behavior on width { enabled: !Theme.reduceMotion;",
    "segArea.containsMouse",
    "scale: !Theme.reduceMotion && segArea.pressed ? 0.96 : 1",
], "segmented selection glides, but snaps with Reduce Motion")

check("apps/lib/SidebarRow.qml", [
    "enabled: row.enabled",
    "if (!event.isAutoRepeat && row.enabled)",
    "scale: !Theme.reduceMotion && tap.pressed ? 0.985 : 1",
], "disabled sidebar rows remain inert with subtle enabled feedback")

check("apps/lib/Glass.qml", [
    "Behavior on pressScale { enabled: !Theme.reduceMotion;",
    "Behavior on lift { enabled: !Theme.reduceMotion;",
    "duration: Theme.reduceMotion ? 0 : 140",
    "duration: Theme.reduceMotion ? 0 : 155",
    "duration: Theme.reduceMotion ? 0 : 190",
], "glass motion disables gracefully without GPU-specific paths")

check("apps/lib/MenuList.qml", [
    "opacity: row.lit ? 1 : 0",
    "duration: Theme.reduceMotion ? 0 : 65",
], "menu hover highlight fades without resizing popup surfaces")

check("apps/lib/PopupMenu.qml", [
    "vanish.stop()",
    "vanish.action = null",
    "box.cancelPending()",
], "reopening a popover does not execute a previously chosen action")

check("apps/lib/MenuList.qml", [
    "function cancelPending() {",
    "if (flash.running) flash.stop()",
    "Keys.onEscapePressed: { cancelPending(); dismissed() }",
], "Escape cancels menu actions pending the selection flash")

check("apps/lib/AppWindow.qml", [
    "An inactive window gently recedes without dimming its document.",
    "opacity: win.active ? 0 : 1",
    "enabled: !Theme.reduceMotion",
], "inactive windows recede through a non-interactive toolbar layer")

check("shell/Dock.qml", [
    "property bool tooltipReady: false",
    "id: tooltipDwell",
    "interval: 300",
    "onEntered: { tile.tooltipReady = false; tooltipDwell.restart() }",
    "onExited: { tooltipDwell.stop(); tile.tooltipReady = false }",
    "Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.popover } }",
], "Dock hover dwell suppresses tooltip flicker and honors Reduce Motion")

check("shell/Notifications.qml", [
    "duration: bannerList.still ? 0 : 260",
    "Behavior on x { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }",
    "enabled: !drag.active && !Theme.reduceMotion",
], "notification dismissal and stack transitions avoid unintended motion")

check("shell/ControlCenter.qml", [
    "Behavior on color { ColorAnimation { duration: Prefs.reduceMotion ? 0 : 120 } }",
    "Behavior on x { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 225;",
], "Control Center respects reduced motion while changing modules")

check("shell/Switcher.qml", [
    "scale: sw.open || Theme.reduceMotion ? 1 : 0.92",
    "Behavior on scale { enabled: !Theme.reduceMotion; Spring { spring: Theme.popover } }",
], "switcher panel appears in place under Reduce Motion")

check("shell/MissionControl.qml", [
    "scale: !Theme.reduceMotion && (tileHover.hovered || desk.target) ? 1.025 : 1",
    "Behavior on scale { enabled: !Theme.reduceMotion;",
], "Mission Control hover is measured rather than distracting")

if failures:
    print("\n".join("FAIL " + failure for failure in failures), file=sys.stderr)
    raise SystemExit(1)
print("Micro-interaction source contracts passed")
