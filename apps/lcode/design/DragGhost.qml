// What you drag from the Library or the outline: a label that follows the
// pointer and carries a payload ({ entry } to add, { move: id } to move) to
// the canvas's or outline's drop areas.
import QtQuick
import "../../lib"
import "../../lib/theme"

Item {
    id: ghost
    property var payload: null
    property string title: ""
    property string symbol: ""
    property bool dragging: false
    signal finished()
    width: label.implicitWidth + 44
    height: 30
    visible: dragging
    z: 3000
    Drag.active: dragging
    Drag.keys: ["lcode/component"]
    Drag.hotSpot.x: 12
    Drag.hotSpot.y: 15

    function prepare(p, t, s, x, y) { payload = p; title = t; symbol = s; ghost.x = x - 12; ghost.y = y - 15 }
    function begin() { dragging = true }
    function finish() {
        if (!dragging) return
        Drag.drop()
        dragging = false
        finished()
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.dark ? "#ee2c2c2e" : "#f5ffffff"
        border { width: 1; color: Theme.accent }
    }
    Symbol { x: 12; anchors.verticalCenter: parent.verticalCenter; name: ghost.symbol || "square-dashed"; size: 15; tone: "accent" }
    Text {
        id: label
        x: 34
        anchors.verticalCenter: parent.verticalCenter
        text: ghost.title
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
    }
}
