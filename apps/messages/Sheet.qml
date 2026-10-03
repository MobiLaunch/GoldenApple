// A confirmation sheet over the window: a title, a sentence and two buttons.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: sheet
    property string title
    property string text
    property string confirmText: "OK"
    property bool destructive: false
    signal confirmed()
    signal cancelled()
    anchors.fill: parent
    z: 60
    Rectangle { anchors.fill: parent; color: "#33000000"; TapHandler { onTapped: sheet.cancelled() } }
    Glass {
        role: "menu"
        anchors.centerIn: parent
        width: 300
        height: body.implicitHeight + 36
        radius: 22
        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 8
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: sheet.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold } }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: sheet.text; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            Row {
                topPadding: 8
                spacing: 8
                Button { width: (body.width - 8) / 2; text: "Cancel"; onClicked: sheet.cancelled() }
                Button { width: (body.width - 8) / 2; text: sheet.confirmText; prominent: true; destructive: sheet.destructive; onClicked: sheet.confirmed() }
            }
        }
    }
    Keys.onEscapePressed: cancelled()
}
