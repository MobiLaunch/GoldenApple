import QtQuick
// An app window: centred in the space the menu bar and Dock leave, with
// Hyprland's shadow and the backdrop blurred behind it.
Surface {
    id: fw
    property string title
    property size minimumSize
    property size maximumSize
    property var parentWindow
    color: "white"
    width: implicitWidth || 900
    height: implicitHeight || 600
    readonly property real __top: PreviewDesktop.reserved("top")
    readonly property real __bottom: PreviewDesktop.reserved("bottom")
    __x: Math.round((PreviewDesktop.screen.width - width) / 2)
    __y: Math.round(__top + Math.max(8, (PreviewDesktop.screen.height - __top - __bottom - height) / 2))
    __layer: 2
    __rounding: 22                        // decoration:rounding (design/dist/hyprland-motion.conf)
    __glass: !__preview.env["GG_PREVIEW_FLAT"]
    __shadow: !__preview.env["GG_PREVIEW_FLAT"]
    Component.onCompleted: if (__preview.env["GG_PREVIEW_DEBUG"]) console.log("window", width, height, __x, __y, visible, __frame.parent)
}
