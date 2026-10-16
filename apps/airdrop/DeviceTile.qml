// One device nearby, as AirDrop shows it: a round picture with the device's
// glyph, its name and what it is underneath. Drop files on it to send them;
// click it to choose files. While sending, a ring around it fills, and the
// line underneath says how it went.
import QtQuick
import QtQuick.Shapes
import "../lib"
import "../lib/theme"

Item {
    id: tile
    property var device: ({})
    readonly property var transfer: device.transfer || null
    readonly property bool busy: !!transfer && (transfer.state === "waiting" || transfer.state === "sending")
    readonly property real progress: transfer && transfer.total > 0 ? transfer.sent / transfer.total : 0
    signal chosen()
    signal dropped(var paths)
    signal cancelRequested()
    width: 132
    height: 150

    // Picture colours by device kind, like the Mac's generic device avatars.
    readonly property var palette: ({
        mobile: ["#7ad7ff", "#2f7ff0"], desktop: ["#a9b4c6", "#5d6b82"],
        web: ["#8ee39a", "#2ea44f"], headless: ["#ffcf70", "#f08a24"], server: ["#ffcf70", "#f08a24"]
    })
    readonly property var colors: palette[device.deviceType] || palette.desktop
    readonly property string glyph: device.deviceType === "mobile" ? "smartphone"
        : device.deviceType === "web" ? "globe" : device.deviceType === "headless" || device.deviceType === "server" ? "drive"
        : "window"

    Item {
        id: picture
        width: 84; height: 84
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
        scale: drop.containsDrag ? 1.12 : area.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 140; easing.type: Easing.OutBack } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: tile.colors[0] }
                GradientStop { position: 1; color: tile.colors[1] }
            }
            border { width: drop.containsDrag ? 3 : 0; color: Theme.accent }
            Symbol { anchors.centerIn: parent; name: tile.glyph; size: 30; tone: "white" }
        }
        // Progress: a ring that fills clockwise from the top.
        Shape {
            anchors.fill: parent
            visible: tile.busy
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.dark ? "#33ffffff" : "#1f000000"
                strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 42; centerY: 42; radiusX: 40; radiusY: 40; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: Theme.accent
                strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 42; centerY: 42; radiusX: 40; radiusY: 40; startAngle: -90
                    sweepAngle: tile.transfer && tile.transfer.state === "sending" ? Math.max(4, 360 * tile.progress) : 0
                    Behavior on sweepAngle { NumberAnimation { duration: 155 } }
                }
            }
        }
        // Waiting for the other side to accept: the ring breathes.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border { width: 4; color: Theme.accent }
            visible: !!tile.transfer && tile.transfer.state === "waiting"
            SequentialAnimation on opacity {
                running: !!tile.transfer && tile.transfer.state === "waiting" && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { from: 0.25; to: 1; duration: 610; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0.25; duration: 610; easing.type: Easing.InOutSine }
            }
        }
    }

    Text {
        id: name
        anchors { top: picture.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.device.alias || "Device"
        elide: Text.ElideRight
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
    }
    Text {
        anchors { top: name.bottom; topMargin: 1; horizontalCenter: parent.horizontalCenter }
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tile.transfer ? (tile.transfer.message || "") : (tile.device.deviceModel || "")
        elide: Text.ElideRight
        color: tile.transfer && tile.transfer.state === "sent" ? Theme.accent
             : tile.transfer && (tile.transfer.state === "declined" || tile.transfer.state === "failed") ? "#ff453a"
             : Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
    }

    MouseArea {
        id: area
        anchors.fill: picture
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: tile.busy ? tile.cancelRequested() : tile.chosen()
    }
    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (d) => {
            const paths = (d.urls || []).map((u) => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter((p) => p)
            if (paths.length) tile.dropped(paths)
        }
    }
    Accessible.role: Accessible.Button
    Accessible.name: (tile.device.alias || "Device") + (tile.busy ? ", sending" : "")
}
