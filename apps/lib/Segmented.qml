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
    implicitWidth: row.implicitWidth + 4; implicitHeight: 26

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
        Behavior on x { Spring { spring: Theme.snappy } }
        Behavior on width { Spring { spring: Theme.snappy } }
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
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: modelData
                    color: Theme.label
                    opacity: segArea.pressed ? 0.55 : 1
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    font { family: Theme.fontUi; pixelSize: 12; weight: index === seg.current ? Font.DemiBold : Font.Normal }
                }
                MouseArea { id: segArea; anchors.fill: parent; onClicked: { seg.current = index; seg.picked(index) } }
            }
        }
    }
}
