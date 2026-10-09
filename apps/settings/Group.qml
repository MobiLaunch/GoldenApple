// A group of rows on a rounded card, as System Settings lays them out; rows are
// separated by hairlines that start at the text.
import QtQuick
import "../lib/theme"

Rectangle {
    id: group
    default property alias rows: col.data
    property string title                 // optional heading above the card
    width: parent ? parent.width : 500
    height: col.height + (title ? 30 : 0)
    color: "transparent"

    Text {
        visible: !!group.title
        x: 4; y: 4
        text: group.title
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
    }
    Rectangle {
        y: group.title ? 30 : 0
        width: parent.width; height: col.height
        radius: 14
        color: Theme.dark ? "#2b2b30" : "#f2f3f6"
        border { width: 0.75; color: Theme.dark ? "#39ffffff" : "#ffffffff" }
        // Shallow material only: the surface borrows Golden Gate's bright
        // leading-edge highlight without allocating a backdrop shader for
        // each settings group, so scrolling dozens of rows stays cheap.
        Rectangle {
            anchors { fill: parent; margins: 1 }
            radius: 13
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.dark ? "#0dffffff" : "#aaffffff" }
                GradientStop { position: 1; color: Theme.dark ? "#02000000" : "#00ffffff" }
            }
        }
        Column {
            id: col
            width: parent.width
        }
    }
}
