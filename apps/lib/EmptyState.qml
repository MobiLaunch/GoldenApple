// Shared empty/error state for CitronOS applications.
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

    // It settles in as it appears, rather than popping into place.
    property real enter: 1
    function appear() { if (Theme.reduceMotion) return; enter = 0; rise.restart() }
    onVisibleChanged: if (visible) appear()
    Component.onCompleted: if (visible) appear()
    NumberAnimation { id: rise; target: root; property: "enter"; to: 1; duration: 340; easing.type: Easing.OutCubic }

    Column {
        id: col
        anchors.centerIn: parent
        opacity: root.enter
        transform: Translate { y: (1 - root.enter) * 10 }
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
            font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.text
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
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
