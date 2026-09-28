// A Mac checkbox with its label and an optional explanation under it.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: box
    property bool checked: false
    property string text
    property string detail
    width: parent ? parent.width : 400
    height: Math.max(20, col.height)

    Rectangle {
        y: 1
        width: 16; height: 16; radius: 4
        color: box.checked ? Theme.accent : (Theme.dark ? "#26ffffff" : "#ffffff")
        border { width: box.checked ? 0 : 1; color: Theme.dark ? "#4dffffff" : "#40000000" }
        Symbol { anchors.centerIn: parent; visible: box.checked; name: "checkmark"; tone: "white"; size: 12 }
    }
    Column {
        id: col
        x: 26; width: parent.width - 26
        spacing: 3
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: box.text
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
        }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            visible: !!box.detail
            text: box.detail
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12 }
        }
    }
    TapHandler { onTapped: box.checked = !box.checked }
}
