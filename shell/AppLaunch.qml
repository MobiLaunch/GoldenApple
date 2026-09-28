// App launch: the tapped icon grows into the app's window, as on iOS.
//
// A card starts exactly over the icon (Dock tile or Spotlight row), springs to
// where the window will open and shows the app's icon on the window colour, like
// an iOS launch screen, while the app starts. When Hyprland maps the window, the
// card springs onto its real frame (keeping its momentum, so the motion bends
// rather than restarts) and dissolves into it. Hyprland itself only fades the
// window in (windowsIn popin 96% in hyprland.conf), so the two hand over cleanly.
//
// Launch with launch(entry, rect) where rect is the icon in this screen's
// coordinates. It also runs under Qt's software renderer (VMs without 3D): the
// card is plain rectangles and images, and only its area is redrawn.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "theme"
import "components"

PanelWindow {
    id: launcher
    readonly property bool enabled: true

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-launch"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}   // never takes input

    property var entry: null
    property rect from: Qt.rect(0, 0, 0, 0)
    property rect to: Qt.rect(0, 0, 0, 0)
    property string state_: "idle"           // idle | opening | handing-over | cancelling
    // Last window size per app, so the card aims for the right frame next time.
    // Golden Gate's own apps start out known: their windows have a fixed size.
    property var sizes: ({ "org.goldengate.Calculator": { w: 229, h: 405 } })
    // Apps whose window isn't the usual window colour (Calculator is always dark).
    readonly property var windowColors: ({ "org.goldengate.Calculator": "#24292d" })

    // Where the window will appear: Hyprland centres new windows in the space the
    // menu bar and Dock leave free.
    function estimate(e) {
        const s = sizes[e?.id] ?? { w: Math.min(960, width * 0.62), h: Math.min(640, height * 0.62) }
        const top = Theme.sizeMenubar, bottom = Theme.sizeDockIcon + 22
        return Qt.rect(Math.round((width - s.w) / 2), Math.round(top + (height - top - bottom - s.h) / 2), s.w, s.h)
    }

    function launch(e, r) {
        entry = e
        from = r
        to = estimate(e)
        for (const [s, v] of [[gx, r.x], [gy, r.y], [gw, r.width], [gh, r.height]]) s.jump(v)
        fade.stop(); card.opacity = 1
        state_ = "opening"
        aim(to)
        giveUp.restart()
        e.execute()
    }
    function aim(r) { gx.target = r.x; gy.target = r.y; gw.target = r.width; gh.target = r.height }

    // The window is up: land on its frame, then let it show through.
    function landOn(r) {
        if (r) {
            to = r
            if (entry) { const s = launcher.sizes; s[entry.id] = { w: r.width, h: r.height }; launcher.sizes = s }
            aim(r)
        }
        state_ = "handing-over"
        handOver.restart()
    }

    function reset() { state_ = "idle"; entry = null; giveUp.stop(); findWindow.stop() }

    // The app never opened a window: fall back into the icon.
    Timer {
        id: giveUp
        interval: 8000
        onTriggered: { launcher.state_ = "cancelling"; launcher.aim(launcher.from); fade.restart() }
    }
    // Give the window a moment to draw its first frame under the card.
    Timer { id: handOver; interval: 140; onTriggered: fade.restart() }
    NumberAnimation {
        id: fade
        target: card; property: "opacity"; to: 0
        duration: 260; easing.type: Easing.OutCubic
        onFinished: launcher.reset()
    }

    // New windows, from Hyprland's event socket.
    property string pendingAddress: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "openwindow" || launcher.state_ !== "opening") return
            launcher.pendingAddress = "0x" + event.parse(4)[0]
            giveUp.stop()
            Hyprland.refreshToplevels()
            findWindow.tries = 0
            findWindow.restart()
        }
    }
    Timer {
        id: findWindow
        property int tries: 0
        interval: 40; repeat: true
        onTriggered: {
            const t = Hyprland.toplevels.values.find((w) => w.lastIpcObject?.address === launcher.pendingAddress)
            const o = t?.lastIpcObject
            if (o?.at && o?.size) {
                stop()
                launcher.landOn(Qt.rect(o.at[0] - launcher.screen.x, o.at[1] - launcher.screen.y, o.size[0], o.size[1]))
            } else if (++tries > 12) {
                stop(); launcher.landOn(null)
            }
        }
    }

    // Spring: quick and nearly critically damped, like an iOS app opening.
    SpringValue { id: gx; response: 0.46; dampingFraction: 0.9 }
    SpringValue { id: gy; response: 0.46; dampingFraction: 0.9 }
    SpringValue { id: gw; response: 0.46; dampingFraction: 0.9 }
    SpringValue { id: gh; response: 0.46; dampingFraction: 0.9 }

    Item {
        id: card
        visible: launcher.state_ !== "idle"
        x: gx.value; y: gy.value; width: gw.value; height: gh.value
        // 0 while the card is still the icon, 1 once it has the window's size.
        readonly property real grow: {
            const span = Math.max(1, launcher.to.width - launcher.from.width)
            return Math.max(0, Math.min(1, (width - launcher.from.width) / span))
        }
        function ease(a, b, t) { const u = Math.max(0, Math.min(1, (t - a) / (b - a))); return u * u * (3 - 2 * u) }

        // The window's shadow (a nine-patch image, so no shader has to compile on
        // the first launch) and its surface, coming in as the icon grows.
        BorderImage {
            anchors { fill: parent; leftMargin: -34; rightMargin: -34; topMargin: -38; bottomMargin: -30 }
            source: Qt.resolvedUrl("assets/card-shadow.png")
            border { left: 56; right: 56; top: 60; bottom: 52 }
            opacity: surface.opacity
        }
        Rectangle {
            id: surface
            anchors.fill: parent
            radius: Math.min(width, height) * 0.2237 * (1 - card.grow) + Theme.radiusWindow * card.grow
            color: launcher.windowColors[launcher.entry?.id] ?? Theme.windowBg
            opacity: card.ease(0.06, 0.4, card.grow)
            border { width: 1; color: Theme.dark ? "#26ffffff" : "#1a000000" }
        }
        // The icon: fills the card at first (so it starts as the Dock icon itself),
        // then settles in the middle, like an iOS launch screen.
        Image {
            readonly property real s: {
                const start = Math.min(card.width, card.height)
                const t = card.ease(0, 0.55, card.grow)
                return start * (1 - t) + Math.min(96, start) * t
            }
            width: s; height: s
            anchors.centerIn: parent
            source: launcher.entry ? Quickshell.iconPath(launcher.entry.icon, "application-x-executable") : ""
            sourceSize: Qt.size(256, 256)
            smooth: true; mipmap: true
        }
    }
}
