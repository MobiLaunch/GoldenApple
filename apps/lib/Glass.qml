// Liquid Glass, by role. Each role is a material from design/tokens.json, so a
// caller says what the glass is for and never paints its own tint:
//   clear    shell glass over the wallpaper (Dock, widgets, lock screen)
//   regular  panels (Control Center, notifications, Spotlight, the switcher)
//   menu     menus and popovers, thicker and more opaque
//   control  small controls on a window (toolbar groups, buttons, pop-ups)
//   sidebar  window sidebars
//   dock     the Dock: smoked graphite, so icons stay vivid on real GPUs
// The layers, as Apple describes them: a neutral tint (glass takes its colour
// from what is behind it), a lens band that gathers light inside the edge, a
// one-pixel specular rim lit from the top left and bright all the way round,
// the darker inner edge on the far side (macOS 27) with the slab's inner
// face catching the light just inside it (its thickness), a top light catch,
// a soft light that follows the pointer across the glass, and a shadow that
// follows the interaction: the glass lifts under the pointer and gives when
// pressed. HyprGlass blurs the backdrop where a surface exposes one.
// `tint` stays settable for stained glass (the accent on a default button,
// red on an error banner); Tinted style and Reduce Transparency only ever
// thicken it.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "theme"

Item {
    id: root
    property real radius: 26
    // `variant` is the older name for the two roles it had; `role` wins.
    property string variant: "regular"
    property string role: variant === "clear" ? "clear" : "regular"
    readonly property QtObject material: role === "clear" ? Theme.glassClear
        : role === "menu" ? Theme.menu
        : role === "control" ? Theme.glassControl
        : role === "sidebar" ? Theme.glassSidebar
        : role === "dock" ? Theme.glassDock
        : Theme.glassRegular
    readonly property bool clearMaterial: role === "clear"
    property color tint: material.tint
    property color rim: material.rim
    property color rimLow: material.rimLow
    property color shine: material.shine
    property color edge: material.edge
    property bool filled: false
    property bool pressed: false
    property bool hovered: false
    // Width of the lens band; never more than a little under half the radius,
    // so a small control's band doesn't fill it.
    property real lens: material.lens
    property color shadow: "transparent"                // a darker contact shadow (knobs)
    default property alias content: body.data

    // What's behind, bent as through a thick slab (shaders/glasslens.frag):
    // every piece of glass that has a backdrop to bend. A window offers its
    // content (AppWindow), a shell surface the desktop under it, drawn again
    // inside it (the shell's DesktopBackdrop); Backdrops finds the nearest,
    // and glass never bends itself. Off with Reduce Transparency or without
    // a GPU; then the compositor's blur is what's behind.
    property var backdropEntry: { Backdrops.entries; return Backdrops.find(root) }
    onParentChanged: backdropEntry = Qt.binding(() => { Backdrops.entries; return Backdrops.find(root) })
    readonly property var backdrop: backdropEntry?.texture ?? null
    readonly property bool lensing: !!backdrop && !!root.Window.window && visible && width > 0 && height > 0 && !filled
        && !Theme.reduceTransparency && GraphicsInfo.api !== GraphicsInfo.Software
    // Where this glass is in the backdrop's texture. Followed every frame
    // while it bends, so it stays put through moves, springs and scaling.
    property point lensOrigin: Qt.point(0, 0)
    function placeLens() {
        if (!lensing || !backdropEntry.item) return
        const p = root.mapToItem(backdropEntry.item, 0, 0)
        const o = Qt.point(p.x - backdrop.sourceRect.x, p.y - backdrop.sourceRect.y)
        if (o.x !== lensOrigin.x || o.y !== lensOrigin.y) lensOrigin = o
    }
    FrameAnimation { running: root.lensing; onTriggered: root.placeLens() }
    onLensingChanged: { Backdrops.use(backdrop, root, lensing); placeLens() }
    onBackdropChanged: Backdrops.use(backdrop, root, lensing)
    Component.onDestruction: Backdrops.use(null, root, false)

    readonly property real r: Math.min(radius, width / 2, height / 2)
    readonly property real band: Math.min(lens, r * 0.45)
    // The style's floor, raised toward Reduce Transparency's by the Glass
    // slider (clear … solid).
    readonly property real minAlpha: {
        const base = Theme.reduceTransparency ? material.reduced : Theme.glassStyle === "tinted" ? material.tinted : 0
        return base + (Math.max(base, material.reduced) - base) * Math.max(0, Math.min(1, Theme.glassSolidity))
    }
    // Over bent content the tint thins, so the bending shows through it.
    readonly property color shownTint: Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a * (lensing ? 0.6 : 1), minAlpha))

    // The press: the glass gives a few pixels whatever its size and bounces
    // back (macOS 27); under the pointer it lifts a pixel. Transforms, so
    // callers can still animate `scale` and `y`.
    property real pressScale: pressed ? Math.max(0.94, 1 - 5 / Math.max(1, Math.max(width, height))) : 1
    Behavior on pressScale { Spring { spring: root.pressed ? Theme.snappy : Theme.bouncy } }
    property real lift: hovered && !pressed && !Theme.reduceMotion ? -1 : 0
    Behavior on lift { Spring { spring: Theme.snappy } }
    transform: [
        Scale { origin.x: root.width / 2; origin.y: root.height / 2; xScale: root.pressScale; yScale: root.pressScale },
        Translate { y: root.lift }
    ]
    // Where the pointer is over the glass, for the light that follows it. A
    // passive handler: it never takes a click or a hover from the controls.
    HoverHandler { id: pointer }

    // The shadow falls only outside the glass. MultiEffect draws its source
    // too, so the shape is masked back out: without that, on a GPU, a solid
    // white panel sat under every pane of glass.
    Rectangle { id: shadowShape; anchors.fill: parent; radius: root.r; color: "#ffffff"; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: shadowShape; source: shadowShape; autoPaddingEnabled: true
        visible: root.material.shadowOpacity > 0
        maskEnabled: true; maskSource: shadowShape; maskInverted: true
        shadowEnabled: true
        shadowColor: root.shadow.a > 0 ? root.shadow : "#000000"
        shadowOpacity: root.material.shadowOpacity + (root.pressed ? -0.06 : root.hovered ? 0.05 : 0)
        shadowBlur: root.role === "control" ? 0.5 : 1.0
        shadowVerticalOffset: root.material.shadowY * (root.pressed ? 0.4 : root.hovered ? 1.3 : 1)
        Behavior on shadowOpacity { NumberAnimation { duration: 160 } }
    }
    // What's behind, through the glass.
    // Made only while it bends: a shader with no texture to sample stalls
    // the OpenGL renderer.
    Loader {
        anchors.fill: parent
        active: root.lensing
        sourceComponent: ShaderEffect {
            property variant source: root.backdrop
            property size size: Qt.size(width, height)
            property real radius: root.r
            property real bevel: Math.min(18, Math.min(width, height) * 0.32)
            property real strength: Math.min(14, Math.min(width, height) * 0.22)
            property real dome: 0.05
            property real dispersion: 0.18
            property real blur: 1.6
            property point origin: root.lensOrigin
            property size texSize: root.backdrop ? Qt.size(root.backdrop.sourceRect.width || root.backdropEntry.item.width,
                                                          root.backdrop.sourceRect.height || root.backdropEntry.item.height) : Qt.size(1, 1)
            fragmentShader: Qt.resolvedUrl("shaders/glasslens.frag.qsb")
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.r
        color: root.filled ? (Theme.dark ? "#e6ffffff" : "#f2ffffff") : root.shownTint
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    // The interaction glow: the glass lights up under the pointer.
    Rectangle {
        anchors.fill: parent
        radius: root.r
        color: "#ffffff"
        opacity: root.pressed ? 0.16 : root.hovered ? 0.07 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    // Light catch along the top.
    Rectangle {
        anchors.fill: parent
        radius: root.r
        visible: !root.filled
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.shine }
            GradientStop { position: Math.min(0.42, 28 / Math.max(1, root.height)); color: "transparent" }
        }
    }
    // Lens band: light gathering toward the edge, brightest top left. Four
    // nested rings of a quarter strength each, so it fades in steps too small
    // to read as a second outline. The ring takes its geometry as properties:
    // an inline component can't see this file's ids.
    component LensRing: ShapePath {
        property real depth
        property real w
        property real h
        property real rr
        property real strength
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: w * 0.35; y2: h
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, strength) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, strength * 0.25) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, strength * 0.55) }
        }
        PathRectangle { x: 0; y: 0; width: w; height: h; radius: rr }
        PathRectangle {
            x: depth; y: depth
            width: Math.max(0, w - 2 * depth); height: Math.max(0, h - 2 * depth)
            radius: Math.max(0, rr - depth)
        }
    }
    Shape {
        id: lensShape
        anchors.fill: parent
        visible: !root.filled && root.band > 1
        preferredRendererType: Shape.CurveRenderer
        // Frosted thickness at the edge, felt more than seen; over dark glass
        // the same white reads twice as strong, so it's halved there.
        readonly property real s: (root.clearMaterial ? 0.10 : 0.08) * (Theme.dark ? 0.5 : 1)
        LensRing { depth: root.band; w: root.width; h: root.height; rr: root.r; strength: lensShape.s }
        LensRing { depth: root.band * 0.68; w: root.width; h: root.height; rr: root.r; strength: lensShape.s }
        LensRing { depth: root.band * 0.42; w: root.width; h: root.height; rr: root.r; strength: lensShape.s }
        LensRing { depth: root.band * 0.2; w: root.width; h: root.height; rr: root.r; strength: lensShape.s }
    }
    // The light that follows the pointer: a soft glow on the glass where the
    // pointer is, as if lit from just above it.
    Shape {
        anchors.fill: parent
        visible: opacity > 0
        opacity: pointer.hovered && !root.filled && !Theme.reduceTransparency ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: pointer.point.position.x; centerY: pointer.point.position.y
                focalX: centerX; focalY: centerY
                centerRadius: Math.min(220, Math.max(root.width, root.height) * 0.6)
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.06 : 0.12) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.r }
        }
    }
    // Rim: the specular hairline, lit top left and bright all the way round,
    // brighter still under the pointer; just inside it the darker edge macOS
    // 27 draws on the far side, and inside that the slab's inner face
    // catching the light, which gives the glass its thickness.
    property real rimGain: pointer.hovered || hovered ? 1.2 : 1
    Behavior on rimGain { NumberAnimation { duration: 160 } }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: root.height
                GradientStop { position: 0; color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, Math.min(1, root.rim.a * root.rimGain)) }
                GradientStop { position: 0.3; color: Qt.rgba(root.rimLow.r, root.rimLow.g, root.rimLow.b, Math.min(1, root.rimLow.a * root.rimGain)) }
                GradientStop { position: 0.7; color: Qt.rgba(root.rimLow.r, root.rimLow.g, root.rimLow.b, Math.min(1, root.rimLow.a * root.rimGain)) }
                GradientStop { position: 1; color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, Math.min(1, root.rim.a * 0.8 * root.rimGain)) }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.r }
            PathRectangle { x: 1; y: 1; width: Math.max(0, root.width - 2); height: Math.max(0, root.height - 2); radius: Math.max(0, root.r - 1) }
        }
        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: root.height
                GradientStop { position: 0.45; color: "transparent" }
                GradientStop { position: 1; color: root.filled ? "transparent" : root.edge }
            }
            PathRectangle { x: 1; y: 1; width: Math.max(0, root.width - 2); height: Math.max(0, root.height - 2); radius: Math.max(0, root.r - 1) }
            PathRectangle { x: 2; y: 2; width: Math.max(0, root.width - 4); height: Math.max(0, root.height - 4); radius: Math.max(0, root.r - 2) }
        }
        // The inner face: light gathered on the far side, just inside the
        // edge. Only on glass big enough to have a visible thickness.
        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: root.height
                GradientStop { position: 0.4; color: "transparent" }
                GradientStop { position: 1; color: root.filled || Math.min(root.width, root.height) < 28 ? "transparent"
                    : Qt.rgba(root.rimLow.r, root.rimLow.g, root.rimLow.b, root.rimLow.a * 0.9) }
            }
            PathRectangle { x: 2; y: 2; width: Math.max(0, root.width - 4); height: Math.max(0, root.height - 4); radius: Math.max(0, root.r - 2) }
            PathRectangle { x: 3.5; y: 3.5; width: Math.max(0, root.width - 7); height: Math.max(0, root.height - 7); radius: Math.max(0, root.r - 3.5) }
        }
    }
    Item {
        id: body
        anchors.fill: parent
    }
}
