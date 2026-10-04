// The base of every Golden Gate Kit component: a cell its container lays out,
// and inside it the box you see, with the modifiers the App Designer offers —
// frame, alignment, padding, fill, corners, border, shadow, offset, hover and
// tap, and an animated show/hide.
//
// Containers (VStack, HStack, ZStack, Grid, Screen) mark their layout with
// kitAxis/kitAlign; a Box reads them to size and place itself, like SwiftUI:
// in a VStack a box is as wide as its content (up to the stack's width, so
// text wraps) unless its frame says "fill" or a number.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "kit.js" as K
import "../theme"
import ".." as Lib

Item {
    id: cell

    // --------------------------------------------------------- environment
    // { dark, accent, colors, font }, inherited from the enclosing Scope.
    property var env: null
    readonly property var kenv: env ? env : (K.findEnv(parent) || ({ dark: Theme.dark, accent: "", colors: ({}), font: "" }))
    readonly property bool dark: !!kenv.dark
    function c(spec, fallback) { return K.color(spec, kenv, fallback) }

    // -------------------------------------------------------------- frame
    property var frameWidth: "auto"           // "auto" | "fill" | number
    property var frameHeight: "auto"
    property real minWidth: 0
    property real maxWidth: 0                 // 0: no limit
    property real minHeight: 0
    property real maxHeight: 0
    property string align: ""                 // overrides the container's alignment for this box
    property var padding: 0                   // number or [top, right, bottom, left]
    property real offsetX: 0
    property real offsetY: 0

    // --------------------------------------------------------- appearance
    property var background: null             // a fill (see kit.js)
    property string foreground: ""            // text and symbol colour
    property real cornerRadius: 0
    property real borderWidth: 0
    property string borderColor: "separator"
    property real shadowRadius: 0
    property real shadowX: 0
    property real shadowY: 4
    property string shadowColor: "black"
    property real shadowOpacity: 0.2
    property bool clipContent: false
    property string hoverEffect: "none"       // none | highlight | lift | scale
    property string transition: "fade"        // none | fade | scale | slide
    property bool shown: true
    property bool tappable: false
    property string accessibilityLabel: ""
    signal tapped()

    // For components: their content's natural size, and the space inside the padding.
    property real contentWidth: 0
    property real contentHeight: 0
    readonly property real innerWidth: Math.max(0, box.width - pad.left - pad.right)
    readonly property real innerHeight: Math.max(0, box.height - pad.top - pad.bottom)
    readonly property color foregroundColor: c(foreground, c("label"))
    default property alias content: inner.data
    readonly property alias box: box

    // ---------------------------------------------------------- container
    readonly property Item container: parent && parent.kitAxis !== undefined ? parent : null
    readonly property string axis: container ? container.kitAxis : ""
    readonly property var pad: K.edges(padding)
    readonly property bool fillsWidth: frameWidth === "fill"
    readonly property bool fillsHeight: frameHeight === "fill"

    function clampW(w) { if (minWidth > 0) w = Math.max(w, minWidth); if (maxWidth > 0) w = Math.min(w, maxWidth); return Math.max(0, w) }
    function clampH(h) { if (minHeight > 0) h = Math.max(h, minHeight); if (maxHeight > 0) h = Math.min(h, maxHeight); return Math.max(0, h) }

    readonly property real naturalWidth: clampW(typeof frameWidth === "number" ? frameWidth : contentWidth + pad.left + pad.right)
    readonly property real naturalHeight: clampH(typeof frameHeight === "number" ? frameHeight : contentHeight + pad.top + pad.bottom)

    implicitWidth: naturalWidth
    implicitHeight: fillsHeight || axis === "screen" || axis === "hscroll" ? clampH(contentHeight + pad.top + pad.bottom) : box.height
    // Containers that stretch their cells (VStack across, HStack down, Grid,
    // ZStack, a screen, a scroll view's content).
    anchors.fill: axis === "z" || axis === "screen" ? parent : undefined
    anchors.left: axis === "scroll" ? parent.left : undefined
    anchors.right: axis === "scroll" ? parent.right : undefined
    anchors.top: axis === "hscroll" ? parent.top : undefined
    anchors.bottom: axis === "hscroll" ? parent.bottom : undefined
    Layout.fillWidth: axis === "v" || axis === "grid" || ((axis === "h" || axis === "z") && fillsWidth)
    Layout.fillHeight: axis === "h" || ((axis === "v" || axis === "grid") && fillsHeight)
    Layout.preferredWidth: naturalWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: typeof frameWidth === "number" ? frameWidth : minWidth
    Layout.maximumWidth: typeof frameWidth === "number" ? frameWidth : (maxWidth > 0 && fillsWidth ? maxWidth : Number.POSITIVE_INFINITY)

    // Where the box sits in its cell.
    readonly property string alignH: {
        const a = align || (container ? container.kitAlign : "center")
        if (axis === "z") return /leading/i.test(a) ? "leading" : /trailing/i.test(a) ? "trailing" : "center"
        return axis === "v" || axis === "grid" || axis === "" ? a : "center"
    }
    readonly property string alignV: {
        const a = align || (container ? container.kitAlign : "center")
        if (axis === "z") return /^top/i.test(a) ? "top" : /^bottom/i.test(a) ? "bottom" : "center"
        return axis === "h" ? a : "center"
    }

    // ------------------------------------------------------ show and hide
    property real appear: shown ? 1 : 0
    Behavior on appear { enabled: cell.transition !== "none" && !Theme.reduceMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    visible: shown || appear > 0.001
    Accessible.name: accessibilityLabel

    // ------------------------------------------------------------- the box
    Item {
        id: box
        width: {
            let w
            if (typeof cell.frameWidth === "number") w = cell.frameWidth
            else if (cell.fillsWidth || cell.axis === "screen") w = cell.width
            else w = Math.min(cell.contentWidth + cell.pad.left + cell.pad.right, cell.width > 0 ? cell.width : Number.POSITIVE_INFINITY)
            return cell.clampW(w)
        }
        height: {
            if (typeof cell.frameHeight === "number") return cell.clampH(cell.frameHeight)
            if (cell.fillsHeight || cell.axis === "screen" || cell.axis === "hscroll") return cell.clampH(cell.height)
            return cell.clampH(cell.contentHeight + cell.pad.top + cell.pad.bottom)
        }
        x: K.place(cell.alignH, cell.width, width) + cell.offsetX
        y: K.place(cell.alignV, cell.height, height) + cell.offsetY
            + (cell.transition === "slide" ? (1 - cell.appear) * 18 : 0)
            - (cell.hoverEffect === "lift" && hover.hovered ? 2 : 0)
        opacity: cell.transition === "none" ? (cell.shown ? 1 : 0) : cell.appear
        scale: (cell.transition === "scale" ? 0.86 + 0.14 * cell.appear : 1)
             * (cell.hoverEffect === "scale" && hover.hovered ? 1.04 : 1)
             * (press.pressed ? 0.97 : 1)
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: cell.hoverEffect === "lift" && !Theme.reduceMotion; NumberAnimation { duration: 140 } }
        clip: cell.clipContent

        // A soft shadow from stacked translucent rings around the box: drawn
        // the same way in every renderer, and (like CSS) never under the box,
        // so glass and other see-through fills stay clean.
        Repeater {
            model: cell.shadowRadius > 0 || (cell.hoverEffect === "lift" && hover.hovered) ? 10 : 0
            delegate: Shape {
                id: ring
                required property int index
                readonly property real r: Math.max(cell.shadowRadius, cell.hoverEffect === "lift" && hover.hovered ? 14 : 0)
                readonly property real spread: r * (index + 1) / 10
                readonly property real dy: cell.shadowY + (cell.hoverEffect === "lift" && hover.hovered ? 3 : 0)
                readonly property real inset: Math.min(cell.cornerRadius, box.width / 2, box.height / 2)
                anchors.fill: parent
                opacity: (cell.shadowRadius > 0 ? cell.shadowOpacity : 0.18) * (1 - index / 10) / 5
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillRule: ShapePath.OddEvenFill
                    strokeWidth: -1
                    fillColor: cell.c(cell.shadowColor, "black")
                    PathRectangle {
                        x: cell.shadowX - ring.spread / 2; y: ring.dy - ring.spread / 2
                        width: box.width + ring.spread; height: box.height + ring.spread
                        radius: ring.inset + ring.spread / 2
                    }
                    PathRectangle { x: 0; y: 0; width: box.width; height: box.height; radius: ring.inset }
                }
            }
        }

        // Fills.
        readonly property string fill: K.fillType(cell.background)
        Rectangle {
            anchors.fill: parent
            visible: box.fill === "color"
            radius: cell.cornerRadius
            color: box.fill === "color" ? cell.c(cell.background.color, "#00000000") : "transparent"
        }
        Rectangle {
            readonly property var mat: K.material(box.fill === "material" ? cell.background.material : "", cell.kenv)
            anchors.fill: parent
            visible: box.fill === "material"
            radius: cell.cornerRadius
            color: mat.tint
            border { width: 1; color: mat.rim }
            // Light catching the top edge, as on Liquid Glass.
            Rectangle {
                anchors { fill: parent; margins: 1 }
                radius: Math.max(0, parent.radius - 1)
                gradient: Gradient {
                    GradientStop { position: 0; color: cell.dark ? "#0affffff" : "#24ffffff" }
                    GradientStop { position: 0.4; color: "#00ffffff" }
                }
            }
        }
        Shape {
            id: gradientFill
            anchors.fill: parent
            visible: box.fill === "gradient"
            preferredRendererType: Shape.CurveRenderer
            readonly property var stops: box.fill === "gradient" && Array.isArray(cell.background.colors) && cell.background.colors.length
                ? cell.background.colors : ["accent", "purple"]
            readonly property real angle: box.fill === "gradient" ? (+cell.background.angle || 0) : 0
            readonly property real rad: (angle - 90) * Math.PI / 180
            ShapePath {
                strokeWidth: -1
                fillGradient: box.fill === "gradient" && cell.background.radial ? radial : linear
                PathRectangle { width: box.width; height: box.height; radius: Math.min(cell.cornerRadius, box.width / 2, box.height / 2) }
            }
            LinearGradient {
                id: linear
                x1: box.width / 2 - Math.cos(gradientFill.rad) * box.width / 2
                y1: box.height / 2 - Math.sin(gradientFill.rad) * box.height / 2
                x2: box.width / 2 + Math.cos(gradientFill.rad) * box.width / 2
                y2: box.height / 2 + Math.sin(gradientFill.rad) * box.height / 2
                stops: gradientFill.stopObjects
            }
            RadialGradient {
                id: radial
                centerX: box.width / 2; centerY: box.height / 2
                focalX: centerX; focalY: centerY
                centerRadius: Math.max(box.width, box.height) / 2
                stops: gradientFill.stopObjects
            }
            property list<GradientStop> stopObjects
            Component { id: stopComponent; GradientStop {} }
            function rebuild() {
                const out = []
                const n = stops.length
                for (let i = 0; i < n; i++)
                    out.push(stopComponent.createObject(gradientFill, { position: n === 1 ? 0 : i / (n - 1), color: cell.c(stops[i], "#000000") }))
                stopObjects = out
            }
            onStopsChanged: rebuild()
            Component.onCompleted: rebuild()
            Connections { target: cell; function onKenvChanged() { gradientFill.rebuild() } }
        }
        Lib.RoundedImage {
            anchors.fill: parent
            visible: box.fill === "image"
            radius: cell.cornerRadius
            source: box.fill === "image" ? cell.resolveAsset(cell.background.source) : ""
            fillMode: box.fill === "image" && cell.background.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        }

        Item {
            id: inner
            x: cell.pad.left
            y: cell.pad.top
            width: cell.innerWidth
            height: cell.innerHeight
        }

        Rectangle {
            anchors.fill: parent
            visible: cell.borderWidth > 0
            radius: cell.cornerRadius
            color: "transparent"
            border { width: cell.borderWidth; color: cell.c(cell.borderColor, "#22000000") }
        }
        Rectangle {
            anchors.fill: parent
            visible: cell.hoverEffect === "highlight" && hover.hovered
            radius: cell.cornerRadius
            color: cell.dark ? "#14ffffff" : "#0d000000"
        }

        HoverHandler {
            id: hover
            enabled: cell.hoverEffect !== "none" || cell.tappable
            cursorShape: cell.tappable ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            id: press
            enabled: cell.tappable
            onTapped: cell.tapped()
        }
    }

    // Image paths in a design are relative to the app (Assets/…); the Scope
    // knows where that is.
    function resolveAsset(path) {
        if (!path) return ""
        const s = String(path)
        if (/^(file|https?|qrc|image):/.test(s) || s.startsWith("/")) return s.startsWith("/") ? "file://" + s : s
        const base = kenv && kenv.assetBase ? kenv.assetBase : ""
        return base ? base + "/" + s : s
    }
}
