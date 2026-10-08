// What's behind a shell surface's glass, drawn again inside the surface so
// its glass can bend it (ui/Glass.qml, ui/shaders/glasslens.frag): the
// wallpaper, where it is on the screen, and live captures of the windows on
// this screen's desktop that reach under the surface, the most recently used
// on top. It's never shown itself: one texture of it, the size of the
// surface, is what every piece of glass in the surface samples.
//
//   DesktopBackdrop { surface: dock; namespace: "gg-dock" }
//
// The surface's place on the screen comes from Hyprland's list of layer
// surfaces (a layer surface doesn't know it), or is given (`at`, for a popup
// over another surface). The compositor still blurs behind the surface: that
// is what shows where there's no glass, and wherever the lens is off.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../ui/theme"

Item {
    id: bd
    required property var surface
    property string namespace: ""
    property bool includeWindows: true       // false for surfaces under the windows (desktop widgets)
    property point at: Qt.point(0, 0)        // the surface's top-left on its screen
    property bool placed: false
    readonly property var screen: surface.screen
    readonly property bool shown: surface.visible && !Theme.reduceTransparency && GraphicsInfo.api !== GraphicsInfo.Software

    parent: surface.contentItem
    visible: Backdrops.used(texture)       // only ever drawn into the texture (hideSource)
    x: -at.x; y: -at.y
    width: screen?.width ?? 0
    height: screen?.height ?? 0
    z: -1000

    Rectangle { anchors.fill: parent; color: "#1b3f9e" }     // as the wallpaper surface, until its image is in
    Image {
        anchors.fill: parent
        source: "file://" + Prefs.wallpaper
        sourceSize: Qt.size(bd.width, bd.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    // The windows under the surface, bottom to top, live while it shows.
    readonly property var windows: {
        if (!includeWindows || !shown) return []
        const mon = Hyprland.monitorFor(bd.screen)
        const ws = mon?.activeWorkspace?.id
        const ox = mon?.x ?? 0, oy = mon?.y ?? 0
        const r = Qt.rect(at.x, at.y, surface.width, surface.height)
        return Hyprland.toplevels.values
            .map((t) => ({ t: t, o: t.lastIpcObject }))
            .filter(({ o }) => o?.at && o.size && !o.hidden && o.workspace?.id === ws && (o.monitor === undefined || o.monitor === mon?.id))
            .map(({ t, o }) => ({ toplevel: t.wayland, x: o.at[0] - ox, y: o.at[1] - oy, w: o.size[0], h: o.size[1], order: o.focusHistoryID ?? 0 }))
            .filter((w) => w.toplevel && w.x < r.x + r.width && w.x + w.w > r.x && w.y < r.y + r.height && w.y + w.h > r.y)
            .sort((a, b) => b.order - a.order)
    }
    Repeater {
        model: bd.windows
        delegate: ScreencopyView {
            required property var modelData
            x: modelData.x; y: modelData.y
            width: modelData.w; height: modelData.h
            captureSource: bd.shown ? modelData.toplevel : null
            live: bd.shown
        }
    }

    // The texture every piece of glass in the surface samples: the part of
    // the backdrop the surface covers.
    ShaderEffectSource {
        id: texture
        parent: bd.parent
        visible: false
        sourceItem: Backdrops.used(texture) ? bd : null
        hideSource: true
        live: true
        sourceRect: Qt.rect(bd.at.x, bd.at.y, bd.surface.width, bd.surface.height)
        Component.onCompleted: Backdrops.add(bd.parent, bd, texture, bd)
        Component.onDestruction: Backdrops.remove(texture)
    }

    // Where the surface is: the preview harness knows (__x, __y); Hyprland
    // lists every layer surface with its place.
    readonly property var previewAt: bd.surface.__x !== undefined ? Qt.point(bd.surface.__x, bd.surface.__y) : null
    onPreviewAtChanged: locate()
    function locate() {
        if (previewAt) { at = previewAt; placed = true; return }
        if (namespace && !layers.running) layers.running = true
    }
    Process {
        id: layers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null
                try { data = JSON.parse(text) } catch (e) { return }
                const mon = Hyprland.monitorFor(bd.screen)
                const levels = data?.[mon?.name]?.levels ?? {}
                for (const level of Object.values(levels)) {
                    for (const l of level) {
                        if (l.namespace !== bd.namespace || Math.abs(l.w - bd.surface.width) > 2 || Math.abs(l.h - bd.surface.height) > 2) continue
                        bd.at = Qt.point(l.x - (mon?.x ?? 0), l.y - (mon?.y ?? 0))
                        bd.placed = true
                        return
                    }
                }
            }
        }
    }
    Timer { id: relocate; interval: 60; onTriggered: bd.locate() }
    onShownChanged: if (shown) { Hyprland.refreshToplevels(); relocate.restart() }
    Connections {
        target: bd.surface
        ignoreUnknownSignals: true
        function onWidthChanged() { relocate.restart() }
        function onHeightChanged() { relocate.restart() }
    }
    Component.onCompleted: locate()
}
