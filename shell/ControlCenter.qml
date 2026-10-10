// Control Center, as in macOS 26: separate glass controls on a four-column
// grid (capsules, circles, Now Playing, the Display and Sound sliders), Edit
// Controls to add more, and each module's detail view in the same place.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import "ui" as Shared
import "ui/theme"
import "components"

PanelWindow {
    id: cc
    objectName: "controlCenter"
    property bool open: false
    property var notifications
    property bool wifiOn: true
    property string ssid: ""
    property real brightness: 0.6
    property bool brightnessTouched: false
    readonly property bool nightShift: Prefs.nightShift
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var player: Mpris.players.values.length ? Mpris.players.values[0] : null
    // CitronPods M10 provides a private daemon snapshot; no new BlueZ
    // polling or audio control loop in Control Center.
    Shared.CitronPodsService { id: airpods; enabled: cc.open }

    function toggle() { open = !open; if (open) refresh() }
    Connections {
        target: Prefs
        function onFocusErrorChanged() { if (cc.open && Prefs.focusError) cc.showDetail("focus") }
    }

    // A module opens into its detail view in place, as on the Mac: the Wi-Fi
    // networks, the paired Bluetooth devices, the sound outputs.
    property string detail: ""          // "" | "wifi" | "bluetooth" | "sound" | "mirroring"
    property var networks: []           // [{ ssid, signal, secure, active }]
    function showDetail(kind) {
        // Anything else (asked over IPC) had an empty "No Outputs" panel.
        if (!["", "wifi", "bluetooth", "sound", "mirroring", "focus", "display", "media", "airpods"].includes(kind)) return
        detail = kind
        stage.contentY = 0
        // Keep the last networks on screen while rescanning, so the list
        // doesn't collapse and regrow under the pointer.
        if (kind === "wifi") scanProc.running = true
        if (kind === "mirroring") { airplayProbe.running = true; if (!castBrowse.running) castBrowse.running = true }
    }
    function openDetailSettings() {
        const pane = ({wifi:"wifi", bluetooth:"bluetooth", sound:"sound", mirroring:"airplay", focus:"focus", display:"displays", airpods:"airpods"})[detail]
        if (!pane) return
        open = false; run("gg-settings " + pane)
    }
    // AirPlay Receiver: the gg-airplay user service (UxPlay, under
    // apps/mirroring/airplay.py) lets an iPhone, iPad or Mac mirror to this
    // computer. Its state file says who's mirroring, or the code a device
    // that's asking has to type.
    property bool airplayOn: false
    property var airplay: ({})
    readonly property bool mirroring: airplayOn && airplay.connected === true
    function setAirplay(on) {
        airplayOn = on
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "gg-airplay.service"])
    }
    // Stop: the receiver starts again at once, without the device.
    function stopMirroring() { Quickshell.execDetached(["systemctl", "--user", "restart", "gg-airplay.service"]) }
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/gg-airplay.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { cc.airplay = JSON.parse(text()) } catch (e) { cc.airplay = ({}) } }
        onLoadFailed: cc.airplay = ({})
    }
    // Displays this computer can mirror to: Google Cast (Chromecast, Google
    // TV) devices on the network, found over mDNS; Miracast displays are
    // found by Network Displays itself, which does the mirroring.
    property var castDevices: []
    Process {
        id: castBrowse
        command: ["sh", "-c", "command -v avahi-browse >/dev/null && timeout 4 avahi-browse -rtp _googlecast._tcp 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, out = []
                for (const line of text.split("\n")) {
                    const f = line.split(";")
                    if (f[0] !== "=" || f.length < 10) continue
                    const name = (f[9].match(/"fn=([^"]*)"/) ?? [])[1] ?? f[3].replace(/\\032/g, " ")
                    const model = (f[9].match(/"md=([^"]*)"/) ?? [])[1] ?? ""
                    if (!name || seen[name]) continue
                    seen[name] = true
                    out.push({ name: name, model: model })
                }
                cc.castDevices = out.sort((a, b) => a.name.localeCompare(b.name))
            }
        }
    }
    readonly property var sinks: Pipewire.nodes.values.filter((n) => n.isSink && !n.isStream && n.audio)
    readonly property var btDevices: (Bluetooth.defaultAdapter?.devices.values ?? []).filter((d) => d.paired || d.connected)
    // Known networks connect at once; open ones join; a new secured network is
    // joined in Settings, which asks for its password (never on a command line).
    function joinNetwork(ssid) {
        cc.run("sh -c 'nmcli -w 15 connection up id \"$1\" >/dev/null 2>&1 || nmcli -w 15 device wifi connect \"$1\" >/dev/null 2>&1 || gg-settings wifi' sh " + JSON.stringify(ssid))
    }
    function run(cmd) { Hyprland.dispatch("exec " + cmd) }
    function refresh() {
        airdropProbe.running = true
        wifiState.running = true
        ssidProc.running = true
        if (!brightnessApply.running) { brightnessTouched = false; brightProc.running = true }
    }
    function setBrightness(value) {
        brightnessTouched = true
        brightness = Math.max(0.02, Math.min(1, value))
        if (!brightnessApply.running) brightnessApply.start()
        brightnessSave.restart()
    }
    // Coalesce drag events; hardware follows at 25 Hz and the last chosen
    // value is saved once the pointer settles, including after dismissal.
    Timer { id: brightnessApply; interval: 40; onTriggered: cc.run("brightnessctl -q set " + Math.round(cc.brightness * 100) + "%") }
    Timer { id: brightnessSave; interval: 240; onTriggered: Quickshell.execDetached(["gg-pref", "display.brightness", String(cc.brightness)]) }
    function setDarkMode() {
        Theme.dark = !Theme.dark
        run("gsettings set org.gnome.desktop.interface color-scheme " + (Theme.dark ? "prefer-dark" : "default"))
        Quickshell.execDetached(["sh", "-c",
            "d=$HOME/.config/golden-gate; mkdir -p \"$d\"; printf '{ \"mode\": \"%s\" }\\n' \"$1\" > \"$d/appearance.json\"",
            "sh", Theme.dark ? "dark" : "light"])
    }
    function setNightShift() {
        const enabled = !nightShift
        Quickshell.execDetached(["gg-pref", "display.nightShift", enabled ? "true" : "false"])
        run(enabled ? "hyprsunset -t " + Prefs.displayWarmth : "pkill -x hyprsunset")
    }

    visible: open || closeTimer.running
    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    implicitWidth: Math.min(392, (screen ? screen.width : 800) - 20)
    // A fixed-size surface: the panel grows and shrinks inside it. Resizing the
    // layer surface on every frame of that animation made the Wi-Fi and
    // Bluetooth views stutter. Only the panel takes input; HyprGlass draws the
    // glass from the panel's painted shape, not the surface's.
    implicitHeight: (screen ? screen.height : 800) - 16
    mask: Region { item: panel }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-controlcenter"
    // What its glass bends: the desktop under it.
    DesktopBackdrop { surface: cc; namespace: "gg-controlcenter" }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) closeTimer.stop()
        else closeTimer.restart()
        panel.syncPresentation()
    }
    Timer {
        id: closeTimer
        interval: Prefs.reduceMotion ? 1 : 180
        onTriggered: { cc.detail = ""; cc.editing = false }
    }
    HyprlandFocusGrab { windows: [cc]; active: cc.open; onCleared: cc.open = false }
    PwObjectTracker { objects: [cc.sink] }

    Process {
        id: wifiState
        command: ["nmcli", "-t", "radio", "wifi"]
        stdout: SplitParser { onRead: line => cc.wifiOn = line.trim() === "enabled" }
    }
    Process {
        id: ssidProc
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1==\"yes\"{print $2; exit}'"]
        stdout: SplitParser { onRead: line => cc.ssid = line.trim() }
    }
    Process {
        id: scanProc
        // SSID last: it is the one field that may itself contain colons.
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, out = []
                for (const line of text.split("\n")) {
                    const parts = line.split(":")
                    if (parts.length < 4) continue
                    const ssid = parts.slice(3).join(":").replace(/\\:/g, ":").trim()
                    if (!ssid || seen[ssid]) continue
                    seen[ssid] = true
                    out.push({ ssid: ssid, active: parts[0] === "*", signal: parseInt(parts[1]) || 0,
                               secure: parts[2] !== "" && parts[2] !== "--" })
                }
                cc.networks = out.sort((a, b) => b.active - a.active || b.signal - a.signal).slice(0, 10)
            }
        }
    }
    PwObjectTracker { objects: cc.sinks }
    // AirDrop's setting, from the file its service keeps.
    property bool airdropOn: true
    Process {
        id: airdropProbe
        command: ["sh", "-c", 'cat "${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate/airdrop.json" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                try { cc.airdropOn = JSON.parse(text || "{}").discoverable !== "off" } catch (e) { cc.airdropOn = true }
            }
        }
    }
    Process {
        id: airplayProbe
        running: true
        command: ["systemctl", "--user", "is-active", "--quiet", "gg-airplay.service"]
        onExited: (code) => cc.airplayOn = code === 0
    }
    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: SplitParser {
            onRead: line => {
                if (cc.brightnessTouched) return
                const bits = line.split(",")
                if (bits.length > 3) cc.brightness = parseInt(bits[3]) / 100
            }
        }
    }

    // ---------------------------------------------------------- the grid
    // Golden Gate: individual glass circles, capsules and rounded cards.
    // The fixed Wayland surface stays unchanged while its content scrolls.
    readonly property real unit: Math.min(Prefs.tabletMode ? 62 : 56,
        Math.max(Prefs.tabletMode ? 54 : 48, (width - 64) / 4))
    readonly property real gap: 10
    function span(n) { return n * unit + (n - 1) * gap }
    // Control Center is a fixed grid of modules, as on the Mac: its text
    // follows Text Size only a little (up to 115%), so labels never crowd
    // the controls beside them.
    function cs(n) { return Math.round(Math.max(Prefs.tabletMode ? 12 : 10, n)
        * Math.max(1, Math.min(1.15, Theme.textScale))) }

    // Optional controls, chosen with Edit Controls (desktop.json controlCenter.extras).
    readonly property var extraCatalog: [
        { id: "screenshot", name: "Screenshot", icon: "screenshot", run: () => cc.ipc("screenshot toolbar") },
        { id: "record", name: "Screen Recording", icon: "record-screen", run: () => cc.ipc("screenshot record") },
        { id: "calculator", name: "Calculator", icon: "calculator", run: () => cc.launch("org.goldengate.Calculator") },
        { id: "timer", name: "Timer", icon: "timer", run: () => cc.launch("org.goldengate.Clock") },
        { id: "notes", name: "Quick Note", icon: "compose", run: () => cc.launch("org.goldengate.Notes") },
        { id: "lock", name: "Lock Screen", icon: "lock", run: () => { cc.open = false; cc.run("loginctl lock-session") } }
    ]
    readonly property var extras: (Array.isArray(Prefs.data.controlCenter?.extras) ? Prefs.data.controlCenter.extras : ["screenshot"])
        .map((id) => extraCatalog.find((e) => e.id === id)).filter((e) => !!e)
    property bool editing: false
    function setExtras(ids) {
        Prefs.data = Object.assign({}, Prefs.data, { controlCenter: Object.assign({}, Prefs.data.controlCenter ?? {}, { extras: ids }) })
        Quickshell.execDetached(["gg-pref", "controlCenter.extras", JSON.stringify(ids)])
    }
    function toggleExtra(id) {
        const ids = extras.map((e) => e.id)
        setExtras(ids.includes(id) ? ids.filter((x) => x !== id) : ids.concat([id]))
    }
    function ipc(call) { cc.open = false; cc.run("qs -c golden-gate ipc call " + call) }
    function launch(id) {
        cc.open = false
        const entry = DesktopEntries.byId(id)
        if (entry) entry.execute()
    }

    // Every module uses the working canonical glass; no enclosing box or
    // second material implementation obscures its refraction.
    component Module: Glass {
        id: mod
        function bounce() { feedback.tap() }
        pressScale: 1
        transform: [
            Scale { origin.x: mod.width / 2; origin.y: mod.height / 2; xScale: feedback.xScale; yScale: feedback.yScale },
            Translate { y: mod.lift }
        ]
        Shared.TactileFeedback { id: feedback; objectName: mod.objectName + "Motion"; pressed: mod.pressed; enabled: mod.enabled }
        radius: Math.min(32, height / 2)
        role: "regular"
        // Wide per-module shadows were clipped by the rectangular scroller
        // and left hard, blocky bands behind the rounded controls.
        shadowEnabled: false
        // A slightly thicker smoked slab improves separation over wallpaper
        // and makes the smaller controls legible at every brightness level.
        // Keep every module on the same material; no extra full-panel shader.
        lens: 13
        tint: Theme.dark ? Qt.rgba(0.17, 0.18, 0.23, pressed ? 0.83 : hovered ? 0.76 : 0.71)
                         : Qt.rgba(0.94, 0.95, 0.98, pressed ? 0.87 : hovered ? 0.80 : 0.75)
        Behavior on tint { ColorAnimation { duration: Prefs.reduceMotion ? 0 : 120 } }
    }

    // A glyph that pops when its control switches, as SF Symbols bounce.
    component PopSymbol: Symbol {
        id: glyph
        property bool on: false
        property real pop: 1
        onOnChanged: { if (Prefs.reduceMotion) { popAnim.stop(); pop = 1 } else popAnim.restart() }
        transform: Scale { origin.x: glyph.width / 2; origin.y: glyph.height / 2; xScale: glyph.pop; yScale: glyph.pop }
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: glyph; property: "pop"; to: 1.12; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: glyph; property: "pop"; to: 1; duration: 210; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        Connections { target: Prefs; function onReduceMotionChanged() { if (Prefs.reduceMotion) { popAnim.stop(); glyph.pop = 1 } } }
    }

    // The round icon at the start of a capsule: blue while it's on.
    component IconDisc: Rectangle {
        id: disc
        property string icon
        property bool on: false
        property real size: 42
        width: size; height: size; radius: size / 2
        color: on ? Theme.accent : (Theme.dark ? "#2effffff" : "#17000000")
        Behavior on color { ColorAnimation { duration: Prefs.reduceMotion ? 1 : 140 } }
        PopSymbol { anchors.centerIn: parent; name: disc.icon; size: Math.round(disc.size * 0.45); on: disc.on; tone: disc.on ? "white" : "auto" }
    }

    // Wi-Fi, Bluetooth, AirDrop, Focus: its circle switches it; the rest of the
    // capsule opens its detail (or does its one thing).
    component Capsule: Module {
        id: capsule
        property string icon
        property string title
        property string subtitle
        property bool on: false
        property var toggleAction: null
        property bool toggleOnSpace: false
        signal activated()
        function trigger(toggle = false) {
            bounce()
            if (toggle && toggleAction) toggleAction()
            else activated()
        }
        activeFocusOnTab: true
        Keys.onSpacePressed: (event) => {
            if (event.isAutoRepeat) return
            trigger(toggleOnSpace)
        }
        Keys.onReturnPressed: trigger()
        Keys.onEnterPressed: trigger()
        width: cc.span(2); height: cc.unit
        pressed: capTap.pressed
        hovered: capTap.containsMouse
        radius: height / 2
        IconDisc { id: capDisc; x: 8; anchors.verticalCenter: parent.verticalCenter; icon: capsule.icon; on: capsule.on; size: Math.min(32, capsule.height - 12) }
        Column {
            anchors { left: capDisc.right; leftMargin: 9; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            // A module's own name is never cut off ("Bluetoo…"): it shrinks
            // to fit first (a wider font, a longer word, larger Text Size).
            Text {
                objectName: "ccCapsuleTitle:" + capsule.title
                width: parent.width
                text: capsule.title
                color: Theme.label
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 9
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: cc.cs(12); weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: !!capsule.subtitle
                text: capsule.subtitle
                color: Theme.secondaryLabel
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: cc.cs(10) }
            }
        }
        MouseArea {
            id: capTap
            anchors.fill: parent
            hoverEnabled: true
            onClicked: (m) => {
                const onDisc = m.x < capDisc.x + capDisc.width + 4
                capsule.forceActiveFocus()
                capsule.trigger(onDisc)
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: capsule.title
        Accessible.description: capsule.subtitle + (toggleOnSpace ? "; Space toggles, Return opens controls" : "")
        Accessible.checked: capsule.on
        Accessible.onPressAction: trigger()
    }

    // A row in Screen Mirroring's detail (a device, Stop, Other Displays).
    component MirrorRow: Rectangle {
        id: mrow
        property string symbol
        property string title
        property string subtitle
        property bool active: false
        property bool clickable: true
        signal clicked()
        width: parent.width; height: subtitle ? 48 : 40; radius: height / 2
        color: !clickable ? "transparent" : mrowArea.pressed ? Theme.selection : mrowArea.containsMouse ? Theme.menuHighlight : "transparent"
        Rectangle {
            id: mrowIcon
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            width: 26; height: 26; radius: 13
            color: mrow.active ? Theme.accent : Theme.dark ? "#26ffffff" : "#14000000"
            Symbol { anchors.centerIn: parent; name: mrow.symbol; size: 13; tone: mrow.active ? "white" : "auto" }
        }
        Column {
            anchors { left: mrowIcon.right; leftMargin: 9; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            Text { width: parent.width; text: mrow.title; elide: Text.ElideRight; color: Theme.label; font { family: Theme.fontUi; pixelSize: cc.cs(13) } }
            Text {
                visible: !!mrow.subtitle
                width: parent.width; text: mrow.subtitle; elide: Text.ElideRight
                color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: cc.cs(10) }
            }
        }
        MouseArea { id: mrowArea; anchors.fill: parent; hoverEnabled: true; enabled: mrow.clickable; onClicked: mrow.clicked() }
    }
    // True circular controls: the caption sits outside the glass hit target.
    component Circle: Item {
        id: circle
        property string icon
        property string name
        property string scope: "main"
        property bool on: false
        property string badge: ""
        signal activated()
        function trigger() { circleDisc.bounce(); activated() }
        width: cc.unit; height: cc.unit + 24
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: name
        Accessible.checked: on
        Accessible.onPressAction: trigger()
        Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) trigger() }
        Keys.onReturnPressed: trigger()
        Keys.onEnterPressed: trigger()
        Module {
            id: circleDisc
            objectName: "ccCircle:" + (circle.scope === "main" ? "" : circle.scope + ":") + circle.name
            width: cc.unit; height: cc.unit; radius: width / 2
            pressed: circleTap.pressed
            hovered: circleTap.containsMouse
            tint: circle.on ? (Theme.dark ? "#f2fafaff" : Theme.accent)
                : Theme.dark ? "#75484852" : "#75f0f0f6"
            PopSymbol {
                anchors.centerIn: parent
                name: circle.icon; size: 22; on: circle.on
                tone: circle.on ? (Theme.dark ? "dark" : "white") : "auto"
            }
        }
        Text {
            anchors { top: circleDisc.bottom; topMargin: 5; left: parent.left; right: parent.right }
            horizontalAlignment: Text.AlignHCenter
            text: circle.name
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: cc.cs(10); weight: Font.Medium }
        }
        Rectangle {
            visible: !!circle.badge
            x: -2; y: -2; width: 20; height: 20; radius: 10
            color: Theme.dark ? "#65656b" : "#8e8e93"
            Text { anchors.centerIn: parent; text: circle.badge; color: "#ffffff"; font.pixelSize: 14 }
        }
        MouseArea { id: circleTap; anchors.fill: parent; hoverEnabled: true; onClicked: { circle.forceActiveFocus(); circle.trigger() } }
    }

    component SliderTile: Shared.LevelSlider {
        showFocusRing: false
        property string title
        property string lowIcon
        property string highIcon
        signal expand()
        width: cc.unit; height: (cc.unit - 12) * 3 + cc.gap * 2
        label: title
        symbol: highIcon
        expandable: true
        onExpanded: expand()
    }

    component MediaControls: Row {
        id: transport
        property bool large: false
        spacing: large ? 12 : 2
        Repeater {
            model: [
                { icon: "backward", label: "Previous track", enabled: !!cc.player && cc.player.canGoPrevious, action: () => cc.player?.previous() },
                { icon: cc.player?.isPlaying ? "pause" : "play", label: cc.player?.isPlaying ? "Pause" : "Play", enabled: !cc.player || cc.player.canTogglePlaying, action: () => cc.player ? cc.player.togglePlaying() : cc.launch("org.goldengate.Music") },
                { icon: "forward", label: "Next track", enabled: !!cc.player && cc.player.canGoNext, action: () => cc.player?.next() }
            ]
            delegate: Item {
                required property var modelData
                objectName: "ccTransport:" + (transport.large ? "expanded:" : "compact:") + modelData.icon
                width: transport.large ? 48 : 32; height: width
                enabled: modelData.enabled
                opacity: enabled ? 1 : 0.3
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.onPressAction: modelData.action()
                Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) modelData.action() }
                Keys.onReturnPressed: modelData.action()
                Keys.onEnterPressed: modelData.action()
                Rectangle {
                    anchors.fill: parent; radius: height / 2
                    color: mediaArea.pressed ? Theme.selection : mediaArea.containsMouse ? Theme.menuHighlight : "transparent"
                }
                Symbol { anchors.centerIn: parent; name: parent.modelData.icon; size: transport.large ? 27 : 21; tone: "auto" }
                MouseArea { id: mediaArea; anchors.fill: parent; hoverEnabled: true; onClicked: { parent.forceActiveFocus(); parent.modelData.action() } }
            }
        }
    }

    // A transparent carrier for individual refracting modules. Scroll inside
    // this fixed surface on short displays rather than cropping controls.
    Item {
        id: panel
        objectName: "ccPanel"
        anchors { top: parent.top; right: parent.right; topMargin: 24 }
        width: cc.span(4) + 28
        height: Math.min(cc.height - 40, (cc.detail ? detailView.implicitHeight : content.implicitHeight) + 28)
        Behavior on height { enabled: !Prefs.reduceMotion; Spring { spring: Theme.snappy } }
        opacity: 0
        scale: 0.975
        transformOrigin: Item.TopRight
        function syncPresentation() {
            entrance.stop()
            departure.stop()
            if (Prefs.reduceMotion) { opacity = cc.open ? 1 : 0; scale = 1; return }
            if (cc.open) {
                if (opacity === 0) scale = 0.975
                entrance.start()
            } else departure.start()
        }
        Component.onCompleted: syncPresentation()
        ParallelAnimation {
            id: entrance
            NumberAnimation { target: panel; property: "opacity"; to: 1; duration: 100; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: panel; property: "scale"; to: 1.012; duration: 110; easing.type: Easing.OutCubic }
                NumberAnimation { target: panel; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutCubic }
            }
        }
        ParallelAnimation {
            id: departure
            NumberAnimation { target: panel; property: "opacity"; to: 0; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { target: panel; property: "scale"; to: 0.985; duration: 110; easing.type: Easing.OutCubic }
        }
        Connections { target: Prefs; function onReduceMotionChanged() { if (Prefs.reduceMotion) panel.syncPresentation() } }
    }

    // The grid and a module's detail view share the panel: the grid slides
    // out to the left as the detail slides in from the right.
    Flickable {
    id: stage
    objectName: "ccViewport"
    z: 2
    anchors.fill: panel
    clip: true
    contentWidth: width
    contentHeight: (cc.detail ? detailView.implicitHeight : content.implicitHeight) + 28
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    onContentHeightChanged: contentY = Math.min(contentY, Math.max(0, contentHeight - height))
    scale: panel.scale
    opacity: panel.opacity
    transformOrigin: Item.TopRight

    Column {
        id: content
        objectName: "ccMainControls"
        x: 14; y: 14
        width: cc.span(4)
        spacing: cc.gap
        opacity: cc.detail ? 0 : 1
        visible: opacity > 0
        enabled: cc.open && !cc.detail
        focus: cc.open && !cc.detail
        Keys.onEscapePressed: cc.open = false
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 160; easing.type: Easing.OutCubic } }
        transform: Translate {
            x: cc.detail && !Prefs.reduceMotion ? -28 : 0
            Behavior on x { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 225; easing.type: Easing.OutCubic } }
        }

        // In use: which apps have the microphone, camera, screen or location,
        // each with its indicator's colour, as at the top of the Mac's.
        Module {
            visible: Privacy.any
            width: cc.span(4)
            height: inUse.implicitHeight + 22
            Column {
                id: inUse
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 14 }
                spacing: 6
                Repeater {
                    model: ["mic", "camera", "screen", "location"].filter((k) => Privacy[k].length)
                    delegate: Row {
                        required property string modelData
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Privacy.colors[parent.modelData]
                        }
                        Text {
                            text: Privacy.names[parent.modelData]
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: cc.cs(12); weight: Font.DemiBold }
                        }
                        Text {
                            text: Privacy[parent.modelData].join(", ")
                            color: Theme.secondaryLabel
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, cc.span(4) - 150)
                            font { family: Theme.fontUi; pixelSize: cc.cs(12) }
                        }
                    }
                }
            }
        }

        // Individual horizontal pills, with fully semicircular ends. No
        // square connectivity container sits behind them.
        Row {
            spacing: cc.gap
            Column {
                objectName: "ccConnectivity"
                width: cc.span(2)
                spacing: cc.gap
                Capsule {
                    objectName: "ccWifi"
                    toggleOnSpace: true
                    height: cc.unit - 12
                    icon: "wifi"; title: "Wi-Fi"; subtitle: cc.wifiOn ? (cc.ssid || "Not Connected") : "Off"; on: cc.wifiOn
                    toggleAction: () => { cc.wifiOn = !cc.wifiOn; Quickshell.execDetached(["nmcli", "radio", "wifi", cc.wifiOn ? "on" : "off"]) }
                    onActivated: cc.showDetail("wifi")
                }
                Capsule {
                    objectName: "ccBluetooth"
                    toggleOnSpace: true
                    height: cc.unit - 12
                    icon: "bluetooth"; title: "Bluetooth"; subtitle: Bluetooth.defaultAdapter?.enabled ? "On" : "Off"; on: Bluetooth.defaultAdapter?.enabled ?? false
                    toggleAction: () => Quickshell.execDetached(["bluetoothctl", "power", (Bluetooth.defaultAdapter?.enabled ?? false) ? "off" : "on"])
                    onActivated: cc.showDetail("bluetooth")
                }
                Capsule {
                    objectName: "ccAirDrop"
                    toggleOnSpace: true
                    height: cc.unit - 12
                    icon: "broadcast"; title: "AirDrop"; subtitle: cc.airdropOn ? "Everyone" : "Receiving Off"; on: cc.airdropOn
                    toggleAction: () => { cc.airdropOn = !cc.airdropOn; Quickshell.execDetached(["gg-airdrop", "--set", cc.airdropOn ? "everyone" : "off"]) }
                    onActivated: { cc.open = false; Quickshell.execDetached(["gg-airdrop"]) }
                }
            }
            SliderTile {
                objectName: "ccBrightness"
                title: "Display"; highIcon: "sun-max"; symbolColor: "#ffd45c"; value: cc.brightness
                onMoved: (value) => cc.setBrightness(value)
                onExpand: cc.showDetail("display")
            }
            SliderTile {
                objectName: "ccVolume"
                title: "Sound"; highIcon: "speaker-wave"; symbolColor: "#25c9df"
                value: cc.sink?.audio?.volume ?? 0
                enabled: !!cc.sink?.audio
                onMoved: (value) => { if (cc.sink?.audio) cc.sink.audio.volume = value }
                onExpand: cc.showDetail("sound")
            }
        }

        Capsule {
            objectName: "ccAirPods"
            visible: airpods.connected
            width: cc.span(4)
            height: cc.unit - 12
            icon: "headphones"
            title: airpods.activeDevice.name || "AirPods"
            subtitle: "Connected · " + (typeof airpods.activeDevice.leftBattery === "number"
                && airpods.activeDevice.leftBattery >= 0 ? airpods.activeDevice.leftBattery + "% left" : "Battery unavailable")
            on: true
            onActivated: cc.showDetail("airpods")
        }

        Capsule {
            objectName: "ccFocus"
            width: cc.span(4); height: cc.unit - 12
            icon: "moon"; title: "Focus"; subtitle: Prefs.focusDnd ? Prefs.focusSummary : "Off"
            on: Prefs.focusDnd
            toggleAction: () => Prefs.setFocus(Prefs.focusDnd ? -1 : 0)
            onActivated: cc.showDetail("focus")
        }
        Row {
            spacing: cc.gap
            Circle { icon: "contrast"; name: "Dark Mode"; on: Theme.dark; onActivated: cc.setDarkMode() }
            Circle { icon: "sun"; name: "Night Shift"; on: cc.nightShift; onActivated: cc.setNightShift() }
            Capsule {
                objectName: "ccMirroring"
                height: cc.unit
                icon: "mirror"; title: "Mirroring"
                subtitle: cc.mirroring ? cc.airplay.device || "Mirroring" : cc.airplayOn ? "Receiving" : "Off"
                onActivated: cc.showDetail("mirroring")
            }
        }
        Module {
            id: nowPlaying
            objectName: "ccNowPlaying"
            width: cc.span(4); height: 76; radius: height / 2
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Now Playing"
            Accessible.description: cc.player?.trackTitle || "Not Playing"
            Accessible.onPressAction: cc.showDetail("media")
            Keys.onSpacePressed: cc.showDetail("media")
            Keys.onReturnPressed: cc.showDetail("media")
            // Behind the transport: opening details never swallows Play.
            MouseArea { anchors.fill: parent; onClicked: cc.showDetail("media") }
            Shared.RoundedImage { x: 12; y: 18; width: 40; height: 40; radius: 12; source: cc.player?.trackArtUrl ?? "" }
            Symbol { x: 22; y: 28; visible: !cc.player?.trackArtUrl; name: "music"; size: 20; tone: "auto" }
            Item {
                x: parent.width - 44; y: 10; width: 28; height: 28
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Sound Output"
                Accessible.onPressAction: cc.showDetail("sound")
                Keys.onSpacePressed: cc.showDetail("sound")
                Keys.onReturnPressed: cc.showDetail("sound")
                Module { anchors.fill: parent; radius: width / 2; pressed: routeTap.pressed; hovered: routeHover.hovered }
                Symbol { anchors.centerIn: parent; name: "airplay"; size: 16; tone: "auto" }
                HoverHandler { id: routeHover }
                TapHandler { id: routeTap; onTapped: cc.showDetail("sound") }
            }
            Text {
                x: 62; y: 14; width: parent.width - 110
                text: cc.player?.trackTitle || "Not Playing"; elide: Text.ElideRight
                color: Theme.label; font { family: Theme.fontUi; pixelSize: cc.cs(14); weight: Font.DemiBold }
            }
            Text {
                x: 62; y: 37; width: parent.width - 176
                text: cc.player?.trackArtist || "Music"; elide: Text.ElideRight
                color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: cc.cs(11) }
            }
            MediaControls { anchors { right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 2 } }
        }

        Grid {
            columns: 4; spacing: cc.gap
            Circle { icon: "stage"; name: "Mission Control"; onActivated: cc.ipc("missioncontrol toggle") }
            Repeater {
                model: cc.extras
                Circle {
                    required property var modelData
                    icon: modelData.icon; name: modelData.name; badge: cc.editing ? "−" : ""
                    onActivated: cc.editing ? cc.toggleExtra(modelData.id) : modelData.run()
                }
            }
        }

        // Edit Controls: the ones you can add, with a + each.
        Column {
            visible: cc.editing
            width: parent.width
            spacing: 8
            Text { text: "Add Controls"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: cc.cs(11); weight: Font.DemiBold } }
            Grid {
                columns: 4
                spacing: cc.gap
                Repeater {
                    model: cc.extraCatalog.filter((e) => !cc.extras.some((x) => x.id === e.id))
                    Circle {
                        required property var modelData
                        icon: modelData.icon; name: modelData.name; badge: "+"
                        onActivated: cc.toggleExtra(modelData.id)
                    }
                }
            }
        }

        Item {
            width: parent.width; height: 32
            Module {
                objectName: "ccEditControls"
                anchors.centerIn: parent
                width: editLabel.implicitWidth + 30; height: 30
                radius: 15
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: cc.editing ? "Done editing controls" : "Edit Controls"
                Accessible.onPressAction: cc.editing = !cc.editing
                Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) cc.editing = !cc.editing }
                Keys.onReturnPressed: cc.editing = !cc.editing
                pressed: editTap.pressed
                hovered: editTap.containsMouse
                Text { id: editLabel; anchors.centerIn: parent; text: cc.editing ? "Done" : "Edit Controls"; color: Theme.label; font { family: Theme.fontUi; pixelSize: cc.cs(12); weight: Font.Medium } }
                MouseArea { id: editTap; anchors.fill: parent; hoverEnabled: true; onClicked: cc.editing = !cc.editing }
            }
        }
    }

    // The detail view's card, the same fill as the grid's modules; it follows
    // the view as it slides and fades.
    Module {
        x: detailView.x - 8; y: detailView.y - 6
        width: detailView.width + 16; height: detailView.height + 12
        opacity: detailView.opacity
        visible: detailView.visible
        enabled: false
        transform: Translate { x: detailShift.x }
    }

    // The detail view of one module, in the same panel.
    ColumnLayout {
        id: detailView
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 20; leftMargin: 22; rightMargin: 22 }
        spacing: 2
        opacity: cc.detail ? 1 : 0
        visible: opacity > 0
        enabled: cc.open && !!cc.detail
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 180; easing.type: Easing.OutCubic } }
        transform: Translate {
            id: detailShift
            x: cc.detail || Prefs.reduceMotion ? 0 : 28
            Behavior on x { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 225; easing.type: Easing.OutCubic } }
        }
        focus: cc.detail !== ""
        Keys.onEscapePressed: { cc.detail = ""; stage.contentY = 0 }

        readonly property string title: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", sound: "Sound Output", mirroring: "Screen Mirroring", focus: "Focus", display: "Display", media: "Now Playing", airpods: "AirPods" })[cc.detail] ?? ""
        readonly property bool hasSwitch: cc.detail === "wifi" || cc.detail === "bluetooth"
        readonly property bool on: cc.detail === "wifi" ? cc.wifiOn : (Bluetooth.defaultAdapter?.enabled ?? false)

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2; Layout.rightMargin: 4
            Layout.preferredHeight: 34
            spacing: 6
            Rectangle {
                width: 24; height: 24; radius: 12
                activeFocusOnTab: true
                Keys.onSpacePressed: cc.detail = ""
                Keys.onReturnPressed: cc.detail = ""
                Accessible.onPressAction: cc.detail = ""
                color: backArea.pressed ? Theme.selection : backArea.containsMouse ? Theme.fill : "transparent"
                Symbol { anchors.centerIn: parent; name: "chevron-left"; size: 11; tone: "auto" }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: cc.detail = "" }
                Accessible.role: Accessible.Button
                Accessible.name: "Back"
            }
            Text {
                Layout.fillWidth: true
                text: detailView.title
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: cc.cs(15); weight: Font.Bold }
            }
            Shared.Switch {
                objectName: "ccDetailSwitch"
                showFocusRing: false
                visible: detailView.hasSwitch
                checked: detailView.on
                onToggled: {
                    if (cc.detail === "wifi") {
                        cc.wifiOn = !cc.wifiOn
                        Quickshell.execDetached(["nmcli", "radio", "wifi", cc.wifiOn ? "on" : "off"])
                        if (cc.wifiOn) scanProc.running = true
                    } else {
                        Quickshell.execDetached(["bluetoothctl", "power", detailView.on ? "off" : "on"])
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.bottomMargin: 4; height: 0.5; color: Theme.separator }

        Column {
            visible: cc.detail === "display" || cc.detail === "sound"
            Layout.fillWidth: true
            spacing: 14
            Shared.LevelSlider {
                showFocusRing: false
                objectName: "ccExpandedLevel"
                anchors.horizontalCenter: parent.horizontalCenter
                width: 80; height: 204
                label: cc.detail === "display" ? "Display brightness" : "Sound volume"
                symbol: cc.detail === "display" ? "sun-max" : "speaker-wave"
                symbolColor: cc.detail === "display" ? "#ffd45c" : "#25c9df"
                value: cc.detail === "display" ? cc.brightness : cc.sink?.audio?.volume ?? 0
                enabled: cc.detail === "display" || !!cc.sink?.audio
                onMoved: (value) => {
                    if (cc.detail === "display") cc.setBrightness(value)
                    else if (cc.sink?.audio) cc.sink.audio.volume = value
                }
            }
            Row {
                visible: cc.detail === "display"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Circle { scope: "display"; icon: "contrast"; name: "Dark Mode"; on: Theme.dark; onActivated: cc.setDarkMode() }
                Circle { scope: "display"; icon: "sun"; name: "Night Shift"; on: cc.nightShift; onActivated: cc.setNightShift() }
            }
            Text {
                visible: cc.detail === "sound"
                width: parent.width; bottomPadding: 8
                text: "Sound Output"; color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: cc.cs(12); weight: Font.DemiBold }
            }
        }

        Column {
            visible: cc.detail === "media"
            objectName: "ccMediaDetail"
            Layout.fillWidth: true
            spacing: 16
            Shared.RoundedImage {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(240, parent.width - 16); height: width
                radius: 28; source: cc.player?.trackArtUrl ?? ""
                Symbol { anchors.centerIn: parent; visible: !cc.player?.trackArtUrl; name: "music"; size: 64; tone: "gray" }
            }
            Column {
                width: parent.width
                spacing: 4
                Text {
                    width: parent.width; text: cc.player?.trackTitle || "Not Playing"
                    elide: Text.ElideRight; color: Theme.label
                    font { family: Theme.fontUi; pixelSize: cc.cs(18); weight: Font.DemiBold }
                }
                Text {
                    width: parent.width; text: cc.player ? cc.player.trackArtist || cc.player.identity : "Music"
                    elide: Text.ElideRight; color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: cc.cs(13) }
                }
            }
            MediaControls { large: true; anchors.horizontalCenter: parent.horizontalCenter }
            Shared.Slider {
                width: parent.width
                value: cc.sink?.audio?.volume ?? 0
                enabled: !!cc.sink?.audio
                Accessible.name: "Sound volume"
                onMoved: (value) => { if (cc.sink?.audio) cc.sink.audio.volume = value }
            }
            Shared.Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sound Output…"
                onClicked: cc.showDetail("sound")
            }
        }

        Column {
            objectName: "focusDetail"
            visible: cc.detail === "focus"
            Layout.fillWidth: true
            spacing: 8
            Text {
                objectName: "ccFocusStatus"
                width: parent.width; wrapMode: Text.WordWrap
                text: Prefs.focusBusy ? "Saving Focus…" : Prefs.focusError || Prefs.focusSummary
                color: Prefs.focusError ? Theme.accentRed : Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: cc.cs(12) }
            }
            Repeater {
                model: [{label:"For 15 minutes", minutes:15}, {label:"For 1 hour", minutes:60},
                        {label:"For 2 hours", minutes:120}, {label:"Until turned off", minutes:0}]
                delegate: Capsule {
                    required property var modelData
                    objectName: "ccFocusDuration:" + modelData.minutes
                    width: parent.width
                    height: 56
                    icon: "moon"; title: modelData.label
                    enabled: !Prefs.focusBusy
                    onActivated: Prefs.setFocus(modelData.minutes)
                }
            }
            Capsule {
                width: parent.width; height: 56; icon: "moon"; title: "Turn Off Do Not Disturb"
                visible: Prefs.focusDnd; enabled: !Prefs.focusBusy
                onActivated: Prefs.setFocus(-1)
            }
        }

        // Screen Mirroring, as on the Mac: this computer as an AirPlay
        // receiver (who's mirroring, the code a device asking has to type,
        // Stop), then the displays this computer can mirror to.
        Column {
            objectName: "mirroringDetail"
            visible: cc.detail === "mirroring"
            Layout.fillWidth: true
            spacing: 2
            Rectangle {
                width: parent.width; height: 52; radius: 9
                color: "transparent"
                Rectangle {
                    id: airplayIcon
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 26; height: 26; radius: 13
                    color: cc.airplayOn ? Theme.accent : Theme.dark ? "#26ffffff" : "#14000000"
                    Symbol { anchors.centerIn: parent; name: "airplay"; size: 13; tone: cc.airplayOn ? "white" : "auto" }
                }
                Column {
                    anchors { left: airplayIcon.right; leftMargin: 9; right: airplaySwitch.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    Text { text: "AirPlay Receiver"; color: Theme.label; font { family: Theme.fontUi; pixelSize: cc.cs(13) } }
                    Text {
                        objectName: "airplayStatus"
                        width: parent.width
                        text: !cc.airplayOn ? "Mirror your iPhone, iPad or Mac here"
                            : cc.mirroring ? (cc.airplay.device || "A device") + " is mirroring"
                            : cc.airplay.pinPending ? "Code for " + (cc.airplay.device || "your device") + ": " + cc.airplay.pin
                            : cc.airplay.running === false ? "Starting…"
                            : "Ready for iPhone, iPad and Mac"
                        elide: Text.ElideRight
                        color: cc.airplay.pinPending && cc.airplayOn ? Theme.label : Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: cc.cs(10); weight: cc.airplay.pinPending && cc.airplayOn ? Font.DemiBold : Font.Normal }
                    }
                }
                Shared.Switch {
                    id: airplaySwitch
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    checked: cc.airplayOn
                    onToggled: cc.setAirplay(!cc.airplayOn)
                }
            }
            // The code, large, while a device asks for it.
            Text {
                visible: cc.airplayOn && cc.airplay.pinPending === true && !!cc.airplay.pin
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(cc.airplay.pin ?? "").split("").join(" ")
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: cc.cs(28); weight: Font.DemiBold; letterSpacing: 2 }
            }
            MirrorRow {
                objectName: "stopMirroring"
                visible: cc.mirroring
                symbol: "xmark"
                title: "Stop Mirroring"
                subtitle: cc.airplay.device ? "Disconnect " + cc.airplay.device : ""
                onClicked: cc.stopMirroring()
            }
            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
            Text {
                leftPadding: 6; topPadding: 6; bottomPadding: 2
                text: "Mirror This Computer To"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: cc.cs(11); weight: Font.DemiBold }
            }
            Repeater {
                model: cc.castDevices
                delegate: MirrorRow {
                    required property var modelData
                    symbol: "tv"
                    title: modelData.name
                    subtitle: modelData.model || "Google Cast"
                    onClicked: { cc.open = false; cc.run("gnome-network-displays") }
                }
            }
            Text {
                visible: cc.castDevices.length === 0
                leftPadding: 6; bottomPadding: 4
                width: parent.width
                text: castBrowse.running ? "Looking for displays…" : "No Google Cast displays found"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: cc.cs(11) }
            }
            MirrorRow {
                symbol: "mirror"
                title: "Other Displays…"
                subtitle: "Miracast TVs and adapters"
                onClicked: { cc.open = false; cc.run("gnome-network-displays") }
            }
        }

        // AirPods detail uses the existing system pane instead of launching
        // the original separate Qt application.
        ColumnLayout {
            Layout.fillWidth: true
            visible: cc.detail === "airpods"
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: airpods.activeDevice.name || "No AirPods connected"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: cc.cs(15); weight: Font.DemiBold }
            }
            Text {
                Layout.fillWidth: true
                text: airpods.status
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: cc.cs(12) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        { label: "Left", value: airpods.activeDevice.leftBattery },
                        { label: "Right", value: airpods.activeDevice.rightBattery },
                        { label: "Case", value: airpods.activeDevice.caseBattery }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; height: 51; radius: 14
                        color: Theme.fill
                        Column {
                            anchors.centerIn: parent; spacing: 5
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label; color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: cc.cs(11) }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: typeof modelData.value === "number" && modelData.value >= 0
                                    && modelData.value <= 100 ? modelData.value + "%" : "—"
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: cc.cs(12); weight: Font.DemiBold }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: ["Off", "ANC", "Transparency", "Adaptive"]
                    delegate: Rectangle {
                        id: noiseItem
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        height: 34; radius: 17
                        color: airpods.canControl && airpods.state.noiseMode === index ? Theme.accent : Theme.fill
                        opacity: airpods.canControl ? 1 : 0.50
                        Text {
                            anchors.centerIn: parent
                            text: noiseItem.modelData
                            color: airpods.canControl && airpods.state.noiseMode === noiseItem.index ? "white" : Theme.label
                            font { family: Theme.fontUi; pixelSize: cc.cs(11) }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: airpods.canControl
                            onClicked: airpods.setNoiseMode(noiseItem.index)
                        }
                    }
                }
            }
        }

        Text {
            visible: rows.count === 0 && cc.detail !== "airpods" && cc.detail !== "mirroring" && cc.detail !== "focus" && cc.detail !== "display" && cc.detail !== "media"
            Layout.fillWidth: true
            Layout.topMargin: 6; Layout.bottomMargin: 6
            horizontalAlignment: Text.AlignHCenter
            text: cc.detail === "wifi" ? (cc.wifiOn ? (scanProc.running ? "Searching…" : "No Networks") : "Wi-Fi is off")
                : cc.detail === "bluetooth" ? ((Bluetooth.defaultAdapter?.enabled ?? false) ? "No Devices" : "Bluetooth is off")
                : "No Outputs"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: cc.cs(12) }
        }

        // Rows: an icon circle (in the accent when in use), the name, and a
        // lock for a secured network.
        Repeater {
            id: rows
            model: cc.detail === "wifi" ? (cc.wifiOn ? cc.networks : [])
                : cc.detail === "bluetooth" ? ((Bluetooth.defaultAdapter?.enabled ?? false) ? cc.btDevices : [])
                : cc.detail === "sound" ? cc.sinks : []
            delegate: Rectangle {
                id: item
                required property var modelData
                readonly property string label: cc.detail === "wifi" ? modelData.ssid
                    : cc.detail === "bluetooth" ? (modelData.name || modelData.deviceName || "Device")
                    : (modelData.description || modelData.nickname || modelData.name || "Output")
                readonly property bool active: cc.detail === "wifi" ? modelData.active
                    : cc.detail === "bluetooth" ? modelData.connected
                    : modelData === Pipewire.defaultAudioSink
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: height / 2
                color: rowArea.pressed ? Theme.selection : rowArea.containsMouse ? Theme.menuHighlight : "transparent"
                RowLayout {
                    anchors { fill: parent; leftMargin: 6; rightMargin: 10 }
                    spacing: 9
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: item.active ? Theme.accent : Theme.dark ? "#26ffffff" : "#14000000"
                        Symbol {
                            anchors.centerIn: parent
                            name: cc.detail === "wifi" ? "wifi" : cc.detail === "bluetooth" ? "bluetooth" : "speaker-wave"
                            size: 12
                            tone: item.active ? "white" : "auto"
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: item.label
                        elide: Text.ElideRight
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: cc.cs(13); weight: item.active ? Font.DemiBold : Font.Normal }
                    }
                    Symbol {
                        visible: cc.detail === "wifi" && item.modelData.secure
                        name: "lock"; size: 11; tone: "auto"; opacity: 0.45
                    }
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (cc.detail === "wifi") { if (!item.active) cc.joinNetwork(item.modelData.ssid) }
                        else if (cc.detail === "bluetooth") { if (item.active) item.modelData.disconnect(); else item.modelData.connect() }
                        else Pipewire.preferredDefaultAudioSink = item.modelData
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; height: 0.5; color: Theme.separator }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            objectName: "ccDetailSettings"
            visible: cc.detail !== "media"
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: detailView.title + " Settings"
            Accessible.onPressAction: cc.openDetailSettings()
            Keys.onSpacePressed: cc.openDetailSettings()
            Keys.onReturnPressed: cc.openDetailSettings()
            Keys.onEnterPressed: cc.openDetailSettings()
            radius: height / 2
            color: settingsArea.pressed ? Theme.selection : settingsArea.containsMouse ? Theme.menuHighlight : "transparent"
            Text {
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: cc.detail === "mirroring" ? "AirPlay Settings…" : detailView.title.replace(" Output", "") + " Settings…"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: cc.cs(13) }
            }
            MouseArea {
                id: settingsArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: cc.openDetailSettings()
            }
        }
    }
    }
}
