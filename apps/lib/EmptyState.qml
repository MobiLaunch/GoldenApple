// Shared empty/error state for Golden Gate applications.
import QtQuick
import "theme"

Item {
    id: root
    property string symbol: "info"
    property string title: ""
    property string text: ""
    // An optional button under the message (Try Again), kept with it.
    property string actionText: ""
    signal action()
    implicitWidth: 360
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.centerIn: parent
        width: Math.min(460, root.width - 32)
        spacing: 8

        Symbol {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.symbol
            size: 42
            tone: "gray"
            opacity: 0.82
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 18; weight: Font.DemiBold }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.text
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 13 }
        }
        Item { width: 1; height: 6; visible: root.actionText !== "" }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.actionText !== ""
            text: root.actionText
            prominent: true
            onClicked: root.action()
        }
    }
}
