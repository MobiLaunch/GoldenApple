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
    "enabled: sheet.shown",
    "onClicked: if (sheet.dismissible) sheet.close()",
    "if (!shown) {",
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
    'objectName: "filesInfo"',
    "infoDialog.open()",
    "infoDialog.close()",
    "if (confirmEmpty.shown) emptyButton.forceActiveFocus()",
])

require("apps/lcode/Workspace.qml", [
    "property bool debugMotionReady: false",
    "property real presentedDebugHeight: showDebug",
    "enabled: win.debugMotionReady && !Theme.reduceMotion && !win.debugResizing",
    "height: Math.max(0, parent.height - win.presentedDebugHeight)",
    "y: parent.height - win.presentedDebugHeight",
    "resizeCoordinateSpace: editorDock",
    "Math.min(win.width - 150, win.contentX + win.contentWidth - 12)",
    "opacity: room >= 260 ? 1 : 0",
    "enabled: room >= 260",
])
require("apps/lcode/DebugArea.qml", [
    "property Item resizeCoordinateSpace: null",
    "mapToItem(debug.resizeCoordinateSpace || debug, m.x, m.y).y",
    "startY = next",
])
require("apps/lcode/EditorArea.qml", [
    "id: tabTap; onTapped: area.current = tab.index",
    "scale: !Theme.reduceMotion && tabTap.pressed ? 0.985 : 1",
    "visible: height > 0.5",
    "enabled: area.findVisible",
    "NumberAnimation { duration: 170; easing.type: Easing.OutCubic }",
])
require("apps/files/QuickLook.qml", [
    "visible: look.open || card.opacity > 0.001",
    "objectName: \"quickLookCard\"",
    "enabled: look.open",
    "objectName: \"quickLookHitArea\"",
    "status === Image.Ready ? 1 : 0",
    "property size previousImageFit:",
    'if (look.kind === "image") return previousImageFit',
    'picture.status === Image.Error ? "Preview unavailable"',

    "Theme.reduceMotion ? 1 : 0.972",
])
require("apps/lib/ModalSheet.qml", [
    "enabled: sheet.shown",
])
require("apps/lcode/design/Popover.qml", [
    "enabled: pop.shown",
])

require("apps/lcode/Navigator.qml", [
    "opacity: nav.page === 0 ? 1 : 0",
    "enabled: nav.page === 0",
    'objectName: "navigatorFindPage"',
    'objectName: "navigatorIssuesPage"',
    'objectName: "navigatorReportsPage"',
    "NumberAnimation { duration: Theme.reduceMotion ? 0 : 125;",
])
require("apps/lcode/EditorArea.qml", [
    "tabs.positionViewAtIndex(area.current, ListView.Contain)",
    "add: Transition {",
    "remove: Transition {",
    "displaced: Transition {",
    "duration: Theme.reduceMotion ? 0 : 145;",
])
require("apps/files.qml", [
    'function switchView(next) {',
    'after.positionViewAtIndex(keepSelection,',
    'after.contentY = after.originY + fraction * newRange',
    'objectName: "filesGridView"',
    'objectName: "filesListView"',
    'enabled: activeView',
    'duration: Theme.reduceMotion ? 0 : 125;',
])
require("apps/lib/Scroller.qml", [
    "needed && !!flickable && flickable.visible && flickable.enabled",
])
require("apps/lcode/Workspace.qml", [
    'visible: opacity > 0.001',
    "Math.min(win.width - 150, win.contentX + win.contentWidth - 12)",
])
require("apps/lcode/Workspace.qml", [
    'objectName: "workspaceFileInspector"',
    'objectName: "workspaceDesignInspector"',
    'enabled: currentInspector',
    'z: currentInspector ? 1 : 0',
    "NumberAnimation { duration: Theme.reduceMotion ? 0 : 140;",
])
require("apps/lcode/Navigator.qml", [
    "function focusRow(rowIndex) {",
    "positionViewAtIndex(next, ListView.Contain)",
    "const item = tree.itemAtIndex(next)",
    "if (item && item.focusControl) item.focusControl.forceActiveFocus()",
    "event.key === Qt.Key_Up",
    "event.key === Qt.Key_Down",
    "event.key === Qt.Key_Right",
    "event.key === Qt.Key_Left",
    "const parentIndex = nav.rows.findIndex",
    "opacity: tree.keyboardNavigating && fileNodeRow.activeFocus ? 0.75 : 0",
    "checked: nav.page === index",
])
require("apps/lcode/design/DesignInspector.qml", [
    "onPlainChanged: if (plain && tab > 1) tab = 1",
    "onSelChanged: contentY = 0",
    "onTabChanged: contentY = 0",
])
require("apps/lcode/Inspector.qml", [
    "onPathChanged: contentY = 0",
])
require("apps/lib/SidebarRow.qml", [
    "Accessible.selected: row.selected",
    "Accessible.onPressAction: if (row.enabled) row.clicked()",
])
require("apps/lib/ToolbarButton.qml", [
    "Accessible.checked: button.checked",
])
require("apps/files.qml", [
    "id: sortArea",
    "hoverEnabled: true",
    "cursorShape: Qt.PointingHandCursor",
    "onClicked: { parent.forceActiveFocus(); parent.sort() }",
])
require("apps/files.qml", [
    'objectName: "filesMarqueeBackground"',
    'objectName: "filesMarqueeHighlight"',
    'z: -1',
    'preventStealing: true',
    'function selectionBetween(x0, y0, x1, y1) {',
    'const item = grid.itemAtIndex(i)',
    'item.mapToItem(grid, 0, 0)',
    'if (modifiers & Qt.ControlModifier)',
    'else if (modifiers & Qt.ShiftModifier)',
    'files.setSelection(paths, paths[paths.length - 1] ?? "")',
    'files.selectionAnchor = files.selectedPath',
    'visible: marqueeBackground.dragging && grid.activeView',
])
if "nav.selectedPath =" in (ROOT / "apps/lcode/Navigator.qml").read_text(encoding="utf-8"):
    failures.append("Navigator must not imperatively overwrite Workspace's selectedPath binding")

if 'visible: rightEdge - leftEdge > 220' in (ROOT / 'apps/lcode/Workspace.qml').read_text(encoding='utf-8'):
    failures.append("LCode activity toolbar has two competing visible bindings")

require("apps/files.qml", [
    'property string typeAhead: ""',
    "function typeSelect(letter) {",
    "const cycling = typeAhead === char",
    "typeAheadDwell.restart()",
    "function selectAtIndex(index, modifiers) {",
    "event.key === Qt.Key_Home || event.key === Qt.Key_End",
    "event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown",
    'objectName: "filesTypeAheadCue"',
    "Keys.onEscapePressed: confirmEmpty.close()",
])
require("shell/MenuBar.qml", [
    'barMenu.open && !wasOpen && key !== "Window"',
    '&& openTitle !== key) barMenu.reopen()',
])

require("apps/lib/ModalSheet.qml", [
    "property bool closing: false",
    "if (!closing)",
    "closing = true",
    "closing = false",
    "enabled: sheet.shown",
    "onClicked: if (sheet.dismissible) sheet.close()",
])
require("apps/files.qml", [
    'objectName: "filesInfo"',
    "infoDialog.open()",
    "infoDialog.close()",
    "property bool pathCopied: false",
    'text: infoDialog.pathCopied ? "Copied" : "Copy Path"',
    "onClicked: infoDialog.copyPath()",
    "onNavigateRequested: (delta) => {",
    "quickLook.focusPreview()",
])
require("apps/files/QuickLook.qml", [
    "signal navigateRequested(int delta)",
    "function focusPreview() {",
    "Keys.onPressed: (event) => {",
    "look.navigateRequested(-1)",
    "look.navigateRequested(1)",
    "look.openRequested(look.entry)",
])


require("apps/files.qml", [
    "function navigableRows() {",
    "id: favoriteRows",
    "id: volumeRows",
    "function focusRow(step, edge) {",
    "rows[next].forceActiveFocus()",
    "ensureVisible(rows[next])",
    'event.key === Qt.Key_Down',
    'event.key === Qt.Key_Up',
    'event.key === Qt.Key_Home',
    'event.key === Qt.Key_End',
    'objectName: crumb.folded ? "filesCrumbsFolded" : "filesCrumb:" + crumb.c.path',
    "Keys.onReturnPressed: crumbButton.activate()",
    "Keys.onSpacePressed: (event) => {",
    "Accessible.onPressAction: crumbButton.activate()",
])
require("apps/lib/SidebarRow.qml", [
    "row.activeFocus && row.enabled ? 1 : 0",
])
require("apps/settings.qml", [
    "readonly property bool expanded: app.matches.length > 0 && search.input.activeFocus",
    "enabled: expanded",
    "scale: expanded || Theme.reduceMotion ? 1 : 0.984",
    "NumberAnimation { duration: Theme.reduceMotion ? 0 : (suggestions.expanded ? 145 : 100);",
])
require("apps/passwords/helper.py", [
    "def code_remaining(at: float, period: int) -> int:",
    'return period - (int(at) % period)',
    '"remaining": code_remaining(now, spec["period"])',
])
require("tests/passwords-app.py", [
    "H.code_remaining(at, 30) == expected",
    "(29.999, 1)",
    "(30, 30)",
])


if failures:
    print("\n".join("FAIL " + failure for failure in failures), file=sys.stderr)
    raise SystemExit(1)
print("Window choreography: synchronized panels, sheet exit, focus and accessibility contracts passed")
