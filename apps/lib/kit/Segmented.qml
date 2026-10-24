// A choice of a few options, side by side.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property var options: ["First", "Second"]
    property int value: 0
    property string tint: ""
    signal edited(int value)
    property int chosen: value
    onValueChanged: chosen = value
    contentWidth: row.implicitWidth + 4
    contentHeight: 28

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.dark ? "#26ffffff" : "#14000000"
    }
    Row {
        id: row
        x: 2; y: 2
        height: parent.height - 4
        Repeater {
            model: root.options
            delegate: Item {
                id: seg
                required property var modelData
                required property int index
                width: root.frameWidth === "fill" ? (root.innerWidth - 4) / Math.max(1, root.options.length) : segLabel.implicitWidth + 26
                height: row.height
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    visible: root.chosen === seg.index
                    color: root.tint ? root.c(root.tint) : (root.dark ? "#636366" : "#ffffff")
                    border { width: root.dark ? 0 : 0.5; color: "#1f000000" }
                }
                Text {
                    id: segLabel
                    anchors.centerIn: parent
                    text: String(seg.modelData)
                    color: root.chosen === seg.index && root.tint ? K.onColor(String(root.c(root.tint))) : root.foregroundColor
                    font { family: Theme.fontUi; pixelSize: 12; weight: root.chosen === seg.index ? Font.DemiBold : Font.Normal }
                }
                TapHandler { onTapped: { root.chosen = seg.index; root.edited(seg.index) } }
            }
        }
    }
}
