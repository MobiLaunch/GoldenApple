// "Latest Songs ›": a section title that can be clicked to see everything.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: head
    property string text
    property bool more: true
    signal clicked()
    height: 26; width: row.width
    Row {
        id: row
        spacing: 3
        Text {
            text: head.text
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 17; weight: Font.Bold }
        }
        Symbol {
            visible: head.more
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            name: "chevron-right"; tone: "gray"; size: 13
        }
    }
    TapHandler { enabled: head.more; onTapped: head.clicked() }
}
