// Pick one of CitronOS's symbols.
import QtQuick
import "../../lib"
import "../../lib/theme"

Popover {
    id: picker
    property var names: []                     // from the helper (lib/assets/symbols)
    property string value: ""
    property bool allowNone: false
    signal picked(string value)
    panelWidth: 300
    panelHeight: 360
    readonly property var shown: {
        const q = filter.text.trim().toLowerCase()
        return (allowNone ? [""] : []).concat(names.filter((n) => !q || n.includes(q)))
    }
    function show(from, x, y, current) { value = current || ""; filter.text = ""; openAt(from, x, y); filter.input.forceActiveFocus() }

    Column {
        width: parent.width
        spacing: 8
        TextField { id: filter; width: parent.width; height: 28; search: true; placeholder: "Filter Symbols" }
        GridView {
            width: parent.width
            height: 360 - 24 - 36
            clip: true
            cellWidth: width / 7
            cellHeight: cellWidth
            model: picker.shown
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                required property string modelData
                width: GridView.view.cellWidth
                height: width
                Rectangle {
                    anchors { fill: parent; margins: 2 }
                    radius: 7
                    color: picker.value === parent.modelData ? Theme.accent : cellHover.hovered ? Theme.fill : "transparent"
                    Symbol {
                        visible: !!parent.parent.modelData
                        anchors.centerIn: parent
                        name: parent.parent.modelData
                        size: 18
                        tone: picker.value === parent.parent.modelData ? "white" : "auto"
                    }
                    Text { visible: !parent.parent.modelData; anchors.centerIn: parent; text: "None"; color: Theme.secondaryLabel; font.pixelSize: 9 }
                }
                HoverHandler { id: cellHover }
                TapHandler { onTapped: { picker.value = parent.modelData; picker.picked(parent.modelData); picker.close() } }
            }
        }
    }
}
