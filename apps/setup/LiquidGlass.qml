// A Liquid Glass panel: the compositor's shader (compositor/liquid-glass),
// run here over Setup Assistant's own backdrop, which the glass can read
// because the assistant draws it. Without shaders (the software renderer in
// VMs) it falls back to the tint, rim and light catch the shell paints.
import QtQuick

Item {
    id: glass
    property var source                 // ShaderEffectSource of the backdrop
    property Item backdropItem           // the item that source covers
    property real radius: 30
    property real bezel: 28
    property real strength: 34
    property color tint: "#c7f7f7fa"
    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown

    ShaderEffect {
        id: effect
        anchors.fill: parent
        visible: glass.shaders && !!glass.source
        property var tex: glass.source
        property size screenSize: Qt.size(glass.backdropItem ? glass.backdropItem.width : 1, glass.backdropItem ? glass.backdropItem.height : 1)
        property vector4d surfaceRect: Qt.vector4d(0, 0, 1, 1)
        property vector4d itemRect: surfaceRect
        property real radius: glass.radius
        property real bezel: glass.bezel
        property real strength: glass.strength
        property point lightDir: Qt.point(-0.5, -0.86)
        property vector4d tint: Qt.vector4d(glass.tint.r * glass.tint.a, glass.tint.g * glass.tint.a, glass.tint.b * glass.tint.a, glass.tint.a)
        fragmentShader: Qt.resolvedUrl("shaders/liquid-glass.frag.qsb")
        // Where the panel is on screen; it can move (transitions), so follow it.
        function place() {
            if (!glass.backdropItem) return
            const p = glass.mapToItem(glass.backdropItem, 0, 0)
            const r = Qt.vector4d(p.x, p.y, glass.width, glass.height)
            if (r !== surfaceRect) surfaceRect = r
        }
        FrameAnimation { running: effect.visible; onTriggered: effect.place() }
        Component.onCompleted: place()
    }

    // Fallback
    Rectangle {
        anchors.fill: parent
        visible: !effect.visible
        radius: glass.radius
        color: glass.tint
        border { width: 1; color: "#80ffffff" }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: "#4dffffff" }
                GradientStop { position: 0.4; color: "transparent" }
            }
        }
    }
}
