import QtQuick
// A popup over its parent window, at anchor.rect (in the parent's coordinates).
Surface {
    id: popup
    readonly property PopupAnchor anchor: PopupAnchor {}
    color: "white"
    visible: false
    readonly property var __parentFrame: anchor.window?.__frame ?? null
    __x: (__parentFrame ? __parentFrame.x : 0) + anchor.rect.x
    __y: (__parentFrame ? __parentFrame.y : 0) + anchor.rect.y
    __layer: 4
}
