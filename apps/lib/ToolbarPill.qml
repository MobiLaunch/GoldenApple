// Liquid Glass capsule that groups toolbar buttons (36 px, as in the prototype).
//   ToolbarPill { ToolbarButton { symbol: "chevron-left" } ToolbarButton { symbol: "chevron-right" } }
import QtQuick
import "theme"

Item {
    id: pill
    default property alias buttons: row.data
    implicitWidth: row.implicitWidth + 6
    implicitHeight: 36

    // Soft shadow, then the glass body and its rim.
    Rectangle {
        anchors { fill: parent; topMargin: 2; bottomMargin: -2 }
        radius: height / 2
        color: Theme.dark ? "#40000000" : "#12000000"
    }
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.dark ? "#eb3a3a3e" : "#ebffffff"
        border { width: 0.5; color: Theme.dark ? "#2effffff" : "#12000000" }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0
    }
}
