// Control Center slider module: title, end glyphs and a thick draggable track.
import QtQuick
import QtQuick.Layouts
import "../theme"

Glass {
    id: root
    property string title
    property string lowIcon
    property string highIcon
    property real value: 0.5            // 0..1
    signal moved(real value)
    radius: 22

    ColumnLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 11; bottomMargin: 12 }
        spacing: 8
        Text {
            text: root.title
            color: "#ffffff"
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
        }
        RowLayout {
            spacing: 10
            Symbol { name: root.lowIcon; size: 14 }
            Item {
                id: track
                Layout.fillWidth: true
                implicitHeight: drag.containsMouse || drag.pressed ? 10 : 7
                Behavior on implicitHeight { Spring { spring: Theme.snappy } }
                Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.3) }
                Rectangle {
                    height: parent.height
                    width: Math.max(height, parent.width * root.value)
                    radius: height / 2
                    color: "#ffffff"
                    Behavior on width { enabled: !drag.pressed; Spring { spring: Theme.snappy } }
                }
                MouseArea {
                    id: drag
                    anchors { fill: parent; margins: -8 }
                    hoverEnabled: true
                    function set(x) { root.moved(Math.max(0, Math.min(1, (x - 8) / track.width))) }
                    onPressed: (m) => set(m.x)
                    onPositionChanged: (m) => { if (pressed) set(m.x) }
                }
            }
            Symbol { name: root.highIcon; size: 16 }
        }
    }
}
