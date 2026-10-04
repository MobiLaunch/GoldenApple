import QtQuick
import Quickshell
// Stands in for a live window capture: a plain window (title bar with traffic
// lights, a sidebar, a few lines) with the app's icon, so layouts that show
// windows can be reviewed without a compositor.
Item {
    id: view
    property var captureSource: null
    property bool live: false
    property bool paintCursor: false
    readonly property bool hasContent: !!captureSource
    readonly property size sourceSize: Qt.size(width, height)
    readonly property string appId: captureSource?.appId ?? ""
    readonly property bool dark: appId.endsWith("Terminal") || appId.endsWith("Music")
    Rectangle {
        anchors.fill: parent
        radius: Math.min(14, width / 20)
        color: view.dark ? "#1e1e20" : "#fbfbfd"
        border { width: 1; color: "#26000000" }
        clip: true
        Rectangle {
            x: parent.width * 0.012; y: x
            width: parent.width * 0.22; height: parent.height - 2 * y
            radius: parent.radius * 0.7
            color: view.dark ? "#2a2a2d" : "#eceef2"
            Row {
                x: parent.width * 0.08; y: parent.height * 0.035
                spacing: Math.max(2, parent.width * 0.04)
                Repeater {
                    model: ["#ff5f57", "#febc2e", "#28c840"]
                    Rectangle { required property string modelData; width: Math.max(3, view.width * 0.012); height: width; radius: width / 2; color: modelData }
                }
            }
            Column {
                x: parent.width * 0.1; y: parent.height * 0.14
                spacing: parent.height * 0.045
                Repeater {
                    model: 6
                    Rectangle { width: view.width * (0.09 + (index % 3) * 0.02); height: Math.max(2, view.height * 0.018); radius: height / 2; color: view.dark ? "#4a4a4e" : "#c9ccd3" }
                }
            }
        }
        Column {
            x: parent.width * 0.27; y: parent.height * 0.12
            spacing: parent.height * 0.04
            Repeater {
                model: 7
                Rectangle { width: view.width * (0.6 - (index % 4) * 0.08); height: Math.max(2, view.height * 0.02); radius: height / 2; color: view.dark ? "#3a3a3e" : "#dfe1e6" }
            }
        }
        Image {
            anchors { right: parent.right; bottom: parent.bottom; margins: parent.width * 0.06 }
            width: Math.min(parent.width, parent.height) * 0.28; height: width
            source: view.appId ? Quickshell.iconPath(DesktopEntries.byId(view.appId)?.icon ?? view.appId, "application-x-executable") : ""
            sourceSize: Qt.size(256, 256)
            opacity: 0.9
        }
    }
}
