import QtQuick
import Quickshell.Wayland
// A layer-shell surface, placed by its anchors and margins as Hyprland does.
Surface {
    id: panel
    readonly property Edges anchors: Edges {}
    readonly property Margins margins: Margins {}
    property real exclusiveZone: 0
    property int exclusionMode: ExclusionMode.Normal
    property bool aboveWindows: true
    color: "white"

    readonly property real __sw: PreviewDesktop.screen.width
    readonly property real __sh: PreviewDesktop.screen.height
    readonly property bool __owns: exclusiveZone > 0
    readonly property real __top: exclusionMode === ExclusionMode.Normal && !__owns ? PreviewDesktop.reserved("top") : 0
    readonly property real __bottom: exclusionMode === ExclusionMode.Normal && !__owns ? PreviewDesktop.reserved("bottom") : 0

    width: anchors.left && anchors.right ? __sw - margins.left - margins.right : (implicitWidth || 100)
    height: anchors.top && anchors.bottom ? __sh - margins.top - margins.bottom - __top - __bottom : (implicitHeight || 100)
    __x: anchors.left ? margins.left : anchors.right ? __sw - width - margins.right : (__sw - width) / 2
    __y: anchors.top ? margins.top + __top : anchors.bottom ? __sh - height - margins.bottom - __bottom : (__sh - height) / 2
    __layer: [0, 1, 3, 4][WlrLayershell.layer] ?? 3
    __glass: PreviewDesktop.glass.includes(WlrLayershell.namespace)
    __threshold: PreviewDesktop.thresholds[WlrLayershell.namespace] ?? 0.07

    Component.onCompleted: { PreviewDesktop.register(panel); if (__preview.env["GG_PREVIEW_DEBUG"]) console.log("panel", WlrLayershell.namespace, width, height, __sw, margins.left, __top, __bottom, implicitHeight, __x, __y) }
    Component.onDestruction: PreviewDesktop.unregister(panel)
}
