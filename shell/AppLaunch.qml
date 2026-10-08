// App launch: the tapped icon grows into the app's window, as on iOS.
//
// A card starts exactly over the icon (Dock tile or Spotlight row), springs to
// where the window will open and shows the app's icon on the window colour, like
// an iOS launch screen, while the app starts. When Hyprland maps the window, the
// card springs onto its real frame (keeping its momentum, so the motion bends
// rather than restarts) and dissolves into it. Hyprland itself only fades the
// window in (windowsIn popin 96% in hyprland.conf), so the two hand over cleanly.
//
// Closing is the same motion in reverse, as when an iPad app is swiped away:
// when a window closes, a card in its colour with the app's icon starts on
// the window's last frame and springs back down into the app's Dock icon,
// the colour fading as the icon grows to fill it. Hyprland only fades the
// window out underneath (windowsOut fade). Windows are followed from
// Hyprland's events (and a light refresh) so their last frame is known.
//
// Launch with launch(entry, rect) where rect is the icon in this screen's
// coordinates. It also runs under Qt's software renderer (VMs without 3D): the
// card is plain rectangles and images, and only its area is redrawn.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "ui/theme"
import "components"

PanelWindow {
    id: launcher
    readonly property bool enabled: !Prefs.reduceMotion

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-launch"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}   // never takes input
    property var entry: null
    property rect from: Qt.rect(0, 0, 0, 0)
    property rect to: Qt.rect(0, 0, 0, 0)
    property string state_: "idle"           // idle | opening | handing-over | cancelling | closing
    property var dock: null                  // this screen's Dock: where a closing window goes back to
    // Last window size per app, so the card aims for the right frame next time.
    // CitronOS's own apps start out known: their windows have a fixed size.
    property var sizes: ({ "org.goldengate.Web": { w: 1160, h: 760 }, "org.goldengate.Calculator": { w: 229, h: 405 }, "org.goldengate.Weather": { w: 1100, h: 860 }, "org.goldengate.Music": { w: 1180, h: 760 }, "org.goldengate.Notes": { w: 1120, h: 720 }, "org.goldengate.Photos": { w: 1180, h: 780 }, "org.goldengate.Maps": { w: 1280, h: 800 }, "org.goldengate.Settings": { w: 780, h: 700 } })
    // Apps whose window isn't the usual window colour (Calculator is always dark).
    readonly property var windowColors: ({ "org.goldengate.Calculator": "#24292d", "org.goldengate.Weather": "#a4bcd2" })

    // Where the window will appear: Hyprland centres new windows in the space the
    // menu bar and Dock leave free.
    function estimate(e) {
        const size = sizes[e?.id] ?? { w: Math.min(960, width * 0.62), h: Math.min(640, height * 0.62) }
        const top = Theme.sizeMenubar, bottom = Theme.sizeDockIcon + 22
        const s = { w: Math.min(size.w, width - 20), h: Math.min(size.h, height - top - bottom - 20) }
        return Qt.rect(Math.round((width - s.w) / 2), Math.round(top + (height - top - bottom - s.h) / 2), s.w, s.h)
    }

    function launch(e, r) {
        if (!enabled) { e.execute(); return }
        handOver.stop(); findWindow.stop(); giveUp.stop()
        pendingAddress = ""
        entry = e
        from = r
        to = estimate(e)
        for (const [s, v] of [[gx, r.x], [gy, r.y], [gw, r.width], [gh, r.height]]) s.jump(v)
        fade.stop(); card.opacity = 1
        state_ = "opening"
        aim(to)
        giveUp.restart()
        // Ensure a launch initiated from a secondary-screen Dock/Spotlight opens
        // on that screen's active workspace instead of the previously focused one.
        const monitor = Hyprland.monitorFor(launcher.screen)
        if (monitor?.name) Hyprland.dispatch(`focusmonitor ${monitor.name}`)
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

    function reset() { state_ = "idle"; entry = null; pendingAddress = ""; giveUp.stop(); findWindow.stop(); handOver.stop() }

    // ------------------------------------------------------------ closing
    // Every window's last known frame, by address: { app, rect, workspace }.
    property var frames: ({})
    function snapshot() {
        const monitor = Hyprland.monitorFor(launcher.screen)
        const out = {}
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject
            if (!o?.address || !o.at || !o.size || o.hidden) continue
            if (o.monitor !== undefined && monitor && o.monitor !== monitor.id) continue
            out[o.address] = { app: o.class ?? "", workspace: o.workspace?.id ?? -1,
                               rect: Qt.rect(o.at[0] - (monitor?.x ?? 0), o.at[1] - (monitor?.y ?? 0), o.size[0], o.size[1]) }
        }
        frames = out
    }
    Timer { id: resnap; interval: 120; onTriggered: launcher.snapshot() }
    function refreshSoon() { Hyprland.refreshToplevels(); resnap.restart() }
    // Sizes change without an event (a resize by its edge), so a light refresh.
    Timer { interval: 2000; repeat: true; running: launcher.enabled && Hyprland.toplevels.values.length > 0; onTriggered: launcher.refreshSoon() }
    Component.onCompleted: snapshot()

    // A window closed: if it was on this screen's current desktop and its app
    // has a Dock icon, fold it back into the icon.
    function windowClosed(address) {
        const f = frames[address]
        if (!f || !enabled || !dock || state_ === "opening" || state_ === "handing-over") return false
        const active = Hyprland.monitorFor(launcher.screen)?.activeWorkspace?.id
        if (active !== undefined && f.workspace !== active) return false
        const target = dock.iconFor(f.app)
        if (!target) return false
        return fold(target.entry, f.rect, Qt.rect(target.rect.x, height + target.rect.y, target.rect.width, target.rect.height))
    }
    // The opening in reverse: from the window's frame into the icon's.
    function fold(e, windowRect, iconRect) {
        if (!enabled) return false
        handOver.stop(); findWindow.stop(); giveUp.stop(); fade.stop()
        entry = e
        from = iconRect
        to = windowRect
        for (const [s, v] of [[gx, windowRect.x], [gy, windowRect.y], [gw, windowRect.width], [gh, windowRect.height]]) s.jump(v)
        card.opacity = 1
        state_ = "closing"
        aim(iconRect)
        landed.restart()
        return true
    }
    // Home: once the card is the icon again (or after a moment, whatever
    // happens), it goes, leaving the Dock icon where it was.
    Timer {
        id: landed
        interval: 30; repeat: true
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            if (Math.abs(gw.value - launcher.from.width) < 1.5 && Math.abs(gy.value - launcher.from.y) < 1.5 || ++ticks > 40) {
                stop()
                fadeHome.restart()
            }
        }
    }
    NumberAnimation {
        id: fadeHome
        target: card; property: "opacity"; to: 0
        duration: 90; easing.type: Easing.OutCubic
        onFinished: launcher.reset()
    }

    // The app never opened a window: fall back into the icon.
    Timer {
        id: giveUp
        interval: 8000
        onTriggered: { launcher.state_ = "cancelling"; launcher.aim(launcher.from); fade.restart() }
    }
    // Give the window a moment to draw its first frame under the card.
    Timer { id: handOver; interval: 80; onTriggered: fade.restart() }
    NumberAnimation {
        id: fade
        target: card; property: "opacity"; to: 0
        duration: 150; easing.type: Easing.OutCubic
        onFinished: launcher.reset()
    }

    // New windows, from Hyprland's event socket.
    property string pendingAddress: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "closewindow") {
                const raw = event.parse(1)[0] ?? ""
                const address = raw.startsWith("0x") ? raw : "0x" + raw
                launcher.windowClosed(address)
                const f = launcher.frames
                delete f[address]
                launcher.frames = f
                return
            }
            if (["openwindow", "activewindowv2", "movewindowv2", "changefloatingmode", "fullscreen", "workspacev2"].includes(event.name))
                launcher.refreshSoon()
            if (event.name !== "openwindow" || launcher.state_ !== "opening") return
            const parts = event.parse(4)
            const appClass = (parts[2] ?? "").toLowerCase()
            const id = (launcher.entry?.id ?? "").toLowerCase()
            const startup = (launcher.entry?.startupClass ?? "").toLowerCase()
            if (appClass !== id && appClass !== id.split(".").pop() && (!startup || appClass !== startup)) return
            launcher.pendingAddress = parts[0].startsWith("0x") ? parts[0] : "0x" + parts[0]
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
                const monitor = Hyprland.monitorFor(launcher.screen)
                const originX = monitor?.x ?? launcher.screen.x
                const originY = monitor?.y ?? launcher.screen.y
                launcher.landOn(Qt.rect(o.at[0] - originX, o.at[1] - originY, o.size[0], o.size[1]))
            } else if (++tries > 12) {
                stop(); launcher.landOn(null)
            }
        }
    }

    // Spring: quick and nearly critically damped, like an iOS app opening.
    SpringValue { id: gx; response: 0.32; dampingFraction: 0.92 }
    SpringValue { id: gy; response: 0.32; dampingFraction: 0.92 }
    SpringValue { id: gw; response: 0.32; dampingFraction: 0.92 }
    SpringValue { id: gh; response: 0.32; dampingFraction: 0.92 }

    Item {
        id: card
        objectName: "launchCard"
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

