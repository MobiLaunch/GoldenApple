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
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
    }
    Rectangle {
        y: group.title ? 30 : 0
        width: parent.width; height: col.height
        radius: 12
        color: Theme.dark ? "#0dffffff" : "#08000000"
        border { width: 0.5; color: Theme.dark ? "#14ffffff" : "#0d000000" }
        Column {
            id: col
            width: parent.width
        }
    }
}
