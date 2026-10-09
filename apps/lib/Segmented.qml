// A segmented control: a glass selection pill that springs to the chosen
// segment, as in macOS 27.
//   Segmented { options: ["Auto", "Light", "Dark"]; current: 1; onPicked: (i) => … }
import QtQuick
import "theme"

Item {
    id: seg
    property var options: []
    property int current: 0
    signal picked(int index)
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.ComboBox
    Accessible.name: options[current] ?? ""
    function pick(i) {
        if (!enabled || !options.length) return
        i = Math.max(0, Math.min(options.length - 1, i))
        if (current !== i) { current = i; picked(i) }
    }
    Keys.onLeftPressed: pick(current - 1)
    Keys.onRightPressed: pick(current + 1)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Home) { pick(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { pick(options.length - 1); event.accepted = true }
    }
    FocusRing {}
    implicitWidth: row.implicitWidth + 4; implicitHeight: Theme.fh(26)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.dark ? "#1fffffff" : "#12000000"
    }
    Glass {
        id: pill
        y: 2; height: parent.height - 4
        readonly property Item target: rep.count ? rep.itemAt(seg.current) : null
        width: target ? target.width : 0
        x: 2 + (target ? target.x : 0)
        radius: height / 2
        filled: !Theme.dark
        tint: Theme.dark ? "#59636366" : "#ffffffff"
        lens: 4
        Behavior on x { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        Behavior on width { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        shadow: "#1f000000"
    }
    Row {
        id: row
        x: 2; height: parent.height
        Repeater {
            id: rep
            model: seg.options
            delegate: Item {
                required property var modelData
                required property int index
                width: Math.max(56, label.implicitWidth + 24); height: row.height
                Rectangle {
                    anchors { fill: parent; margins: 2 }
                    radius: height / 2
                    color: Theme.dark ? "#ffffff" : "#000000"
                    opacity: index !== seg.current && segArea.containsMouse && seg.enabled ? 0.065 : 0
                    Behavior on opacity {
                        enabled: !Theme.reduceMotion
                        NumberAnimation { duration: 95; easing.type: Easing.OutCubic }
                    }
                }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData
                    color: Theme.label
                    opacity: segArea.pressed ? 0.65 : 1
                    scale: !Theme.reduceMotion && segArea.pressed ? 0.96 : 1
                    Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 80 } }
                    Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: index === seg.current ? Font.DemiBold : Font.Normal }
                }
                MouseArea { id: segArea; anchors.fill: parent; hoverEnabled: true; onClicked: { seg.forceActiveFocus(); seg.pick(index) } }
            }
        }
    }
}

