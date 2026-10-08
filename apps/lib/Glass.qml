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
    // While the app or shell closes, the theme's materials go before the glass
    // does: every read below falls back (nothing drawn) rather than logging a
    // TypeError for each property of each piece of glass.
    readonly property bool clearMaterial: role === "clear"
    property color tint: (material?.tint ?? "transparent")
    property color rim: (material?.rim ?? "transparent")
    property color rimLow: (material?.rimLow ?? "transparent")
    property color shine: (material?.shine ?? "transparent")
    property color edge: (material?.edge ?? "transparent")
    property bool filled: false
    property bool pressed: false
    property bool hovered: false
    // Width of the lens band; never more than a little under half the radius,
    // so a small control's band doesn't fill it.
    property real lens: (material?.lens ?? 0)
    property color shadow: "transparent"                // a darker contact shadow (knobs)
    default property alias content: body.data

    // What's behind, bent as through a thick slab (shaders/glasslens.frag):
    // every piece of glass that has a backdrop to bend. A window offers its
    // content (AppWindow), a shell surface the desktop under it, drawn again
    // inside it (the shell's DesktopBackdrop); Backdrops finds the nearest,
    // and glass never bends itself. Off with Reduce Transparency or without
    // a GPU; then the compositor's blur is what's behind.
    // Looked up again, once things settle, whenever a backdrop comes or goes
    // or the glass or anything above it moves to a new parent. (A binding
    // straight over find() was re-entered while a pop-up menu moved itself
    // onto the window's overlay as it was made: a binding loop.)
    property var backdropEntry: null
    // Watched once made: read while the pieces above are still being made, a
    // parent still to be set (a pop-up menu's, onto the overlay) was a loop.
    property bool made: false
    readonly property var backdropKey: {
        if (!made) return []
        const chain = [Backdrops.entries]
        for (let p = root.parent; p; p = p.parent) chain.push(p)
        return chain
    }
    // (The look-up waits for the next turn; glass gone by then, a closed
    // notification's, is left alone.)
    readonly property var lookup: ({ gone: false })
    onBackdropKeyChanged: { const l = lookup; Qt.callLater(() => { if (!l.gone) root.findBackdrop() }) }
    function findBackdrop() {
        backdropEntry = Backdrops.find(root)
        if (lensing) gatherTransforms()
    }
    readonly property var backdrop: backdropEntry?.texture ?? null
    readonly property bool lensing: !!backdrop && !!root.Window.window && visible && width > 0 && height > 0 && !filled
        && !Theme.reduceTransparency && GraphicsInfo.api !== GraphicsInfo.Software
    // Where this glass is in the backdrop's texture. A binding that depends on
    // the place, size, scale and transforms of every item above the glass and
    // above the backdrop, so it follows a layout, a scroll, a spring or a drag
    // moving any of them, and costs nothing while nothing moves. (Following it
    // every frame instead kept each window with glass redrawing at full rate
    // all the time, which made everything on screen choppy.) The glass's own
    // press and lift aren't counted: the lens moves with them.
    readonly property point lensOrigin: {
        const e = backdropEntry
        if (!lensing || !e?.item || !root.parent) return Qt.point(0, 0)
        root.x; root.y
        watchAncestors(root.parent)
        watchAncestors(e.item)
        for (const f of ancestorTransforms) { f.x; f.y; f.xScale; f.yScale; f.angle; f.origin }
        // Through the scene, not straight to the backdrop's item: mapping
        // between two items asks the other one's window to convert, and a
        // menu's backdrop could still name a window already deleted, which
        // crashed Quickshell. Both are in this window when it's right.
        const s0 = root.parent.mapToItem(null, root.x, root.y)
        const p = e.item.mapFromItem(null, s0.x, s0.y)
        const s = e.texture.sourceRect
        return Qt.point(p.x - s.x, p.y - s.y)
    }
    function watchAncestors(item) {
        for (let p = item; p; p = p.parent) { p.x; p.y; p.width; p.height; p.scale; p.rotation }
    }
    // The Translate, Scale and Rotation transforms above the glass and the
    // backdrop: gathered when it starts bending (or moves to a new parent),
    // as an item's list of transforms can't be watched, only what's in it.
    property var ancestorTransforms: []
    function gatherTransforms() {
        const list = []
        for (const start of [root.parent, backdropEntry?.item ?? null])
            for (let p = start; p; p = p.parent)
                for (let i = 0; i < (p.transform?.length ?? 0); i++) list.push(p.transform[i])
        ancestorTransforms = list
    }
    onLensingChanged: { Backdrops.use(backdrop, root, lensing); if (lensing) gatherTransforms() }
    onBackdropEntryChanged: if (lensing) gatherTransforms()
    onBackdropChanged: Backdrops.use(backdrop, root, lensing)
    Component.onCompleted: made = true
    Component.onDestruction: { lookup.gone = true; Backdrops.use(null, root, false) }

    readonly property real r: Math.min(radius, width / 2, height / 2)
    readonly property real band: Math.min(lens, r * 0.45)
    // The style's floor, raised toward Reduce Transparency's by the Glass
    // slider (clear … solid).
    readonly property real minAlpha: {
        // Without a GPU nothing bends or blurs what's behind, and glass at its
        // usual tint left a menu's text over a sharp, readable desktop.
        const base = Theme.reduceTransparency || GraphicsInfo.api === GraphicsInfo.Software ? (material?.reduced ?? 0) : Theme.glassStyle === "tinted" ? (material?.tinted ?? 0) : 0
        return base + (Math.max(base, (material?.reduced ?? 0)) - base) * Math.max(0, Math.min(1, Theme.glassSolidity))
    }
    // Over bent content the tint thins a little, so the bending shows
    // through it while what's on the glass stays easy to read.
    readonly property color shownTint: Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a * (lensing ? 0.8 : 1), minAlpha))

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

    // The shadow falls only outside the glass, so the glass stays see-through:
    // one pass of shaders/glassshadow.frag (a blurred rounded rectangle with
    // the glass cut out). It was a MultiEffect over a layer, an offscreen
    // texture and several blur passes for every control. Not drawn by Qt's
    // software renderer (no shaders), as before.
    ShaderEffect {
        id: shadowEffect
        readonly property real drop: (root.material?.shadowY ?? 0) * (root.pressed ? 0.4 : root.hovered ? 1.3 : 1)
        property real blurPx: (root.role === "control" ? 0.5 : 1.0) * 32 / 3
        property real pad: Math.ceil(blurPx * 3 + Math.abs(drop))
        x: -pad; y: -pad
        width: root.width + 2 * pad; height: root.height + 2 * pad
        visible: (root.material?.shadowOpacity ?? 0) > 0 && GraphicsInfo.api !== GraphicsInfo.Software
        property size size: Qt.size(width, height)
        property size glass: Qt.size(root.width, root.height)
        property real radius: root.r
        property real sigma: blurPx
        property real offsetY: drop
        property real strength: (root.material?.shadowOpacity ?? 0) + (root.pressed ? -0.06 : root.hovered ? 0.05 : 0)
        property color color: root.shadow.a > 0 ? root.shadow : "#000000"
        Behavior on strength { NumberAnimation { duration: 140 } }
        fragmentShader: Qt.resolvedUrl("shaders/glassshadow.frag.qsb")
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
        Behavior on color { ColorAnimation { duration: 155 } }
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
        Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
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
    Behavior on rimGain { NumberAnimation { duration: 140 } }
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
