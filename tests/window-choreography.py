#!/usr/bin/env python3
"""Guard shared window choreography and sheet/popup lifecycle contracts.

Runtime coverage lives in native-controls.py and files-interactions.py; these
guards make it harder to fork a modal implementation or accidentally animate
one content edge independently of its matching sidebar.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
failures = []


def require(path, pieces):
    data = (ROOT / path).read_text(encoding="utf-8")
    for piece in pieces:
        if piece not in data:
            failures.append(f"{path}: missing {piece!r}")


require("apps/lib/AppWindow.qml", [
    "property real presentedSidebarWidth: Math.max(0, sidebarWidth)",
    "property real presentedTrailingSidebarWidth: Math.max(0, trailingSidebarWidth)",
    "enabled: win.choreographyReady && !Theme.reduceMotion",
    "readonly property real contentX: presentedSidebarWidth",
    "width - contentX - presentedTrailingSidebarWidth",
    "width: win.presentedSidebarWidth; height: parent.height",
    "width: win.presentedTrailingSidebarWidth; height: parent.height",
    "Math.max(0, parent.width - 20)",
    "choreographyReady = true",
    "Math.max(lights.x + lights.width + 16,",
])

require("apps/lib/ModalSheet.qml", [
    "visible: shown || dimmer.opacity > 0.001 || panel.opacity > 0.001",
    "default property alias content: content.data",
    "const active = sheet.Window.window?.activeFocusItem",
    "if (origin && origin.visible && origin.enabled) origin.forceActiveFocus()",
    "enabled: sheet.shown && sheet.dismissible",
    "if (!shown) return",
    "signal closed()",
    "sheet.shown || Theme.reduceMotion ? 1 : 0.985",
])

require("apps/lcode/Sheet.qml", [
    "import \"../lib\" as Shared",
    "Shared.ModalSheet { }",
])
require("apps/lcode/design/Popover.qml", [
    "visible: shown || panel.opacity > 0.001",
    "panel.transformOrigin = above ? Item.Bottom : Item.Top",
    "if (origin && origin.visible && origin.enabled) origin.forceActiveFocus()",
    "enabled: pop.modal && pop.shown",
    "enabled: !Theme.reduceMotion",
])
require("apps/files.qml", [
    "objectName: \"filesEmptyTrashSheet\"",
    "objectName: \"filesEditSheet\"",
    "confirmEmpty.open()",
    "confirmEmpty.close()",
    "editDialog.open()",
    "editDialog.close()",
    "if (confirmEmpty.shown) emptyButton.forceActiveFocus()",
])

if failures:
    print("\n".join("FAIL " + failure for failure in failures), file=sys.stderr)
    raise SystemExit(1)
print("Window choreography: synchronized panels, sheet exit, focus and accessibility contracts passed")
