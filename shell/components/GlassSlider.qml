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
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: title
    function adjust(v) { if (enabled && Number.isFinite(v)) moved(Math.max(0, Math.min(1, v))) }
    Keys.onLeftPressed: adjust(value - 0.05)
    Keys.onRightPressed: adjust(value + 0.05)
    Keys.onUpPressed: adjust(value + 0.05)
    Keys.onDownPressed: adjust(value - 0.05)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Home) { adjust(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { adjust(1); event.accepted = true }
    }
    Accessible.onIncreaseAction: adjust(value + 0.05)
    Accessible.onDecreaseAction: adjust(value - 0.05)
    Rectangle {
        anchors { fill: parent; margins: 2 }
        radius: 20
        color: "transparent"
        border { width: 2; color: Theme.accent }
        visible: opacity > 0
        opacity: root.activeFocus ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 100 } }
    }

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
                implicitHeight: drag.pressed ? 10 : drag.containsMouse ? 8.5 : 7
                Behavior on implicitHeight { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
                Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.3) }
                Rectangle {
                    id: fill
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, root.value))
                    radius: height / 2
                    color: "#ffffff"
                    Behavior on width { enabled: !drag.pressed; Spring { spring: Theme.snappy } }
                }
                // Liquid Glass knob: white at rest; while dragging it grows into a
                // clear glass lens over the track, as in iOS and macOS 26.
                Glass {
                    id: knob
                    property real size: drag.pressed ? 28 : drag.containsMouse ? 18 : 0
                    width: size * 1.35; height: size
                    radius: height / 2
                    x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    visible: size > 0.5
                    filled: !drag.pressed
                    tint: Qt.rgba(1, 1, 1, 0.12)
                    lens: 6
                    Behavior on size { enabled: !Prefs.reduceMotion; Spring { spring: Theme.snappy } }
                }
                MouseArea {
                    id: drag
                    anchors { fill: parent; margins: -8 }
                    hoverEnabled: true
                    function set(x) { if (track.width > 0) root.adjust((x - 8) / track.width) }
                    onPressed: (m) => { root.forceActiveFocus(); set(m.x) }
                    onPositionChanged: (m) => { if (pressed) set(m.x) }
                }
            }
            Symbol { name: root.highIcon; size: 16 }
        }
    }
}

