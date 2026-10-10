import QtQuick
import QtQuick.Effects
// What every preview window shares: a frame in one of the desktop's layers,
// the window colour, and, for glass surfaces and app windows, the backdrop
// blurred behind whatever the window draws (as HyprGlass does).
QtObject {
    id: win
    default property alias data: content.data
    readonly property alias contentItem: content
    property var screen: PreviewDesktop.screen
    property color color: "white"
    property bool visible: true
    property real implicitWidth: 0
    property real implicitHeight: 0
    property real width: implicitWidth
    property real height: implicitHeight
    property QtObject mask
    property var surfaceFormat
    property bool focusable: false

    // Set by the window types.
    property int __layer: 2
    property bool __glass: false
    property real __threshold: 0.07
    property bool __shadow: false
    property real __x: 0
    property real __y: 0
    readonly property Item __frame: frame

    function itemPosition(item) { return item.mapToItem(content, 0, 0) }
    function itemRect(item) { const p = item.mapToItem(content, 0, 0); return Qt.rect(p.x, p.y, item.width, item.height) }
    function mapFromItem(item, x, y) { return item.mapToItem(content, x, y) }

    // Set by FloatingWindow: Hyprland rounds app windows (decoration:rounding).
    property real __rounding: 0

    property Item __frameItem: Item {
        id: frame
        parent: PreviewDesktop.layers[win.__layer] ?? null
        x: win.__x; y: win.__y
        width: win.width; height: win.height
        visible: win.visible

        // Hyprland's window shadow, behind the window's rounded shape.
        RectangularShadow {
            anchors.fill: parent
            visible: win.__shadow
            radius: win.__rounding
            offset.y: 16
            blur: 48
            spread: -6
            color: Qt.rgba(0, 0, 0, 0.30)
        }
        // Hyprland rounds app windows itself (win.__rounding). Not drawn here:
        // in software GL a layer effect blanks the window, so square corners in a
        // preview where an app leaves them to the compositor aren't a defect.
        Item {
            id: body
            anchors.fill: parent

            ShaderEffectSource {
                id: backdropSource
                anchors.fill: parent
                visible: false
                sourceItem: win.__glass ? PreviewDesktop.backdrop : null
                sourceRect: Qt.rect(frame.x, frame.y, frame.width, frame.height)
                live: true
            }
            ShaderEffectSource {
                id: contentSource
                anchors.fill: parent
                visible: false
                sourceItem: win.__glass ? content : null
                live: true
            }
            MultiEffect {
                anchors.fill: parent
                visible: win.__glass
                source: backdropSource
                // No padding: the mask is laid over the effect's whole area, so a
                // padded effect stretched it and blurred beside the glass.
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                saturation: 0.15
                maskEnabled: true
                maskSource: contentSource
                maskThresholdMin: win.__threshold
                maskSpreadAtMin: 0.02
            }
            Rectangle { anchors.fill: parent; color: win.color }
            Item { id: content; anchors.fill: parent }
        }
    }
}
