// A scroll bar as on the Mac, for any Flickable, ListView or GridView. Put
// it beside the view (same parent), not inside it:
//
//   ListView { id: list; … }
//   Scroller { flickable: list }
//
// (or, in a view that's a file's root, inside it: Scroller { parent: list;
// flickable: list }, which keeps it out of the scrolling content)
//
// It sits over the content at the right edge, thin, and shows while you
// scroll (fading a moment after), or all the time when Settings ›
// Appearance › Show scroll bars is Always (Theme.alwaysShowScrollbars).
// Hovering widens it; dragging the knob scrolls; clicking the track pages.
import QtQuick
import "theme"

Item {
    id: s
    property Flickable flickable
    readonly property bool needed: !!flickable && flickable.contentHeight > flickable.height + 1
    readonly property bool wide: hover.hovered || drag.pressed
    property bool active: false
    readonly property bool inside: parent === flickable
    x: flickable ? (inside ? 0 : flickable.x) + flickable.width - width - 2 : 0
    y: flickable ? (inside ? 0 : flickable.y) + 2 : 0
    width: wide ? 12 : 9
    height: flickable ? Math.max(0, flickable.height - 4) : 0
    z: (flickable && !inside ? flickable.z : 0) + 1
    visible: needed && !!flickable && flickable.visible && flickable.enabled
    opacity: needed && (Theme.alwaysShowScrollbars || active || wide) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : (s.opacity > 0 ? 300 : 115) } }
    Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: 125; easing.type: Easing.OutCubic } }
    Accessible.role: Accessible.ScrollBar

    Connections {
        target: s.flickable
        function onContentYChanged() { s.active = true; idle.restart() }
        function onMovingChanged() { if (s.flickable.moving) { s.active = true; idle.stop() } else idle.restart() }
    }
    Timer { id: idle; interval: 900; onTriggered: s.active = false }

    // The track appears when it's hovered (or always shown), as on the Mac.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.dark ? "#14ffffff" : "#0d000000"
        opacity: s.wide || Theme.alwaysShowScrollbars ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 120 } }
    }
    Rectangle {
        id: knob
        readonly property real ratio: s.flickable ? Math.min(1, s.flickable.visibleArea.heightRatio) : 1
        readonly property real pos: s.flickable ? Math.max(0, Math.min(1 - ratio, s.flickable.visibleArea.yPosition)) : 0
        x: 2; width: parent.width - 4
        // A short inspector is allowed to have a short scrollbar, not a
        // 24px thumb that overflows its own track or gets a negative y.
        height: Math.min(s.height, Math.max(24, s.height * ratio))
        y: Math.max(0, s.height - height) * (ratio < 1 ? pos / (1 - ratio) : 0)
        radius: width / 2
        color: Theme.dark ? (s.wide ? "#a6ffffff" : "#80ffffff") : (s.wide ? "#80000000" : "#59000000")
        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : 100 } }
    }
    HoverHandler { id: hover }
    MouseArea {
        id: drag
        anchors.fill: parent
        enabled: s.needed
        property real grab: -1
        onPressed: (m) => {
            if (m.y >= knob.y && m.y <= knob.y + knob.height) { grab = m.y - knob.y; return }
            grab = -1
            // The track pages, toward where it was clicked.
            const f = s.flickable
            const page = f.height * 0.9 * (m.y < knob.y ? -1 : 1)
            f.contentY = Math.max(f.originY, Math.min(f.originY + f.contentHeight - f.height, f.contentY + page))
        }
        onPositionChanged: (m) => {
            if (grab < 0 || !pressed) return
            const f = s.flickable
            const travel = Math.max(1, s.height - knob.height)
            const p = Math.max(0, Math.min(1, (m.y - grab) / travel))
            f.contentY = f.originY + p * Math.max(0, f.contentHeight - f.height)
        }
        onReleased: grab = -1
    }
}
