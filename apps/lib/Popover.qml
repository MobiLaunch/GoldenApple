// A popover: a glass panel with an arrow pointing at what opened it (an
// event in Calendar, a detail in Control Center, a font in LCode).
//   Popover { id: info; anchorItem: button; Column { … } }
//   info.open()
// Below its anchor, or above when there's no room (`edge`). It closes on a
// click outside it, on Escape, or with close(), and gives focus back to what
// opened it. While open, Tab stays inside it. It grows from its arrow; with
// Reduce Motion it fades.
import QtQuick
import QtQuick.Window
import "theme"

Item {
    id: pop
    property Item anchorItem: null
    property string edge: "auto"            // bottom | top | auto
    property real panelWidth: 280
    property real panelHeight: content.childrenRect.height + 28
    property bool shown: false
    property bool dismissOnClickAway: true  // closes on a click outside
    default property alias content: content.data
    readonly property alias panel: panel
    signal closed()

    property Item returnFocus: null
    property Item home: null
    property Item lastInside: null
    visible: shown || panel.opacity > 0.01
    z: 1000

    function open() {
        if (shown || !anchorItem) return
        const win = anchorItem.Window.window
        returnFocus = win ? win.activeFocusItem : null
        home = parent
        parent = anchorItem.Window.contentItem
        place()
        shown = true
        Qt.callLater(() => { const f = focusables(); (f[0] ?? panel).forceActiveFocus() })
    }
    function close() {
        if (!shown) return
        shown = false
        closed()
        const origin = returnFocus
        returnFocus = null
        if (origin && origin.visible && origin.enabled) origin.forceActiveFocus()
    }
    function toggle() { shown ? close() : open() }

    // Where it goes: centred on its anchor, kept inside the window.
    property real ax: 0
    property real ay: 0
    property real aw: 0
    property real ah: 0
    readonly property bool below: edge === "bottom" || (edge === "auto" && ay + ah + 10 + panelHeight <= height - 8)
    function place() {
        const p = anchorItem.mapToItem(pop.parent, 0, 0)
        ax = p.x; ay = p.y; aw = anchorItem.width; ah = anchorItem.height
    }
    anchors.fill: parent

    function inside(item) {
        for (let it = item; it; it = it.parent) if (it === panel) return true
        return false
    }
    function focusables() {
        const out = []
        const walk = (it) => {
            if (!it.visible || !it.enabled) return
            if (it.activeFocusOnTab) out.push(it)
            for (const c of it.children) walk(c)
        }
        walk(content)
        return out
    }
    // Tab stays inside: focus that would leave goes round to the other end.
    Connections {
        target: pop.shown ? pop.Window.window : null
        function onActiveFocusItemChanged() {
            const f = pop.Window.window?.activeFocusItem
            if (!f || pop.inside(f)) { pop.lastInside = f; return }
            const list = pop.focusables()
            if (!list.length) { panel.forceActiveFocus(); return }
            const wasFirst = pop.lastInside === list[0] && list.length > 1
            ;(wasFirst ? list[list.length - 1] : list[0]).forceActiveFocus()
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: pop.shown
        Accessible.ignored: true
        onPressed: (mouse) => { if (pop.dismissOnClickAway) pop.close(); else mouse.accepted = true }
    }

    Item {
        id: panel
        objectName: "popoverPanel"
        focus: true
        enabled: pop.shown
        width: Math.min(pop.panelWidth, pop.width - 16)
        height: Math.min(pop.panelHeight, pop.height - 16)
        x: Math.max(8, Math.min(pop.width - width - 8, pop.ax + pop.aw / 2 - width / 2))
        y: pop.below ? pop.ay + pop.ah + 10 : pop.ay - height - 10
        readonly property real arrowX: pop.ax + pop.aw / 2 - x
        opacity: pop.shown ? 1 : 0
        scale: pop.shown || Theme.reduceMotion ? 1 : 0.94
        transformOrigin: pop.below ? Item.Top : Item.Bottom
        Behavior on opacity { NumberAnimation { duration: pop.shown ? Theme.motion.snappy.ms / 2 : Theme.motion.tap.ms / 2 } }
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.snappy.ms; easing.type: Easing.OutCubic } }
        Keys.onEscapePressed: pop.close()
        Accessible.role: Accessible.Dialog
        Accessible.name: pop.anchorItem?.Accessible.name ?? ""

        // The arrow: a square turned on its corner, half under the panel.
        Rectangle {
            width: 14; height: 14
            rotation: 45
            x: Math.max(Theme.radius.panel, Math.min(panel.width - Theme.radius.panel - width, panel.arrowX - width / 2))
            y: pop.below ? -height / 2 + 1 : panel.height - height / 2 - 1
            color: Theme.windowBg
            border { width: 0.5; color: Theme.separator }
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.panel
            color: Theme.windowBg
            opacity: 0.94
        }
        Glass { anchors.fill: parent; radius: Theme.radius.panel; role: "menu" }
        MouseArea { anchors.fill: parent; Accessible.ignored: true }    // clicks inside stay inside
        Item {
            id: content
            anchors { fill: parent; margins: 14 }
        }
    }
}
