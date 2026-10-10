import QtQuick
import Quickshell
// The preview's screen: Hyprland's layers, bottom to top, and the shell or app
// under review created into them (its windows place themselves).
Window {
    id: root
    property url targetUrl
    property int screenWidth: 1440
    property int screenHeight: 900
    property bool dark: false
    readonly property bool isShell: String(targetUrl).endsWith("/shell.qml")
    width: screenWidth; height: screenHeight
    visible: true
    color: "#0b1f4f"

    Item {
        id: background
        anchors.fill: parent
        // An app on its own: the desktop picture behind it, as the shell would draw.
        Image {
            anchors.fill: parent
            visible: !root.isShell
            source: "file://" + __preview.env["GG_WALLPAPER"]
            fillMode: Image.PreserveAspectCrop
        }
    }
    Item { id: bottom; anchors.fill: parent }
    Item { id: windows; anchors.fill: parent }
    Item { id: top; anchors.fill: parent }
    Item { id: overlay; anchors.fill: parent }

    Component.onCompleted: {
        PreviewDesktop.screen = { name: "eDP-1", width: screenWidth, height: screenHeight, x: 0, y: 0, model: "Preview", devicePixelRatio: 1 }
        PreviewDesktop.layers = [background, bottom, windows, top, overlay]
        PreviewDesktop.backdrop = background
        const c = Qt.createComponent(targetUrl)
        if (c.status === Component.Error) { console.error(c.errorString()); return }
        if (!c.createObject(root)) console.error("preview: could not create " + targetUrl)
    }
}
