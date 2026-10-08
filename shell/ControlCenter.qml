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
    property bool open: false
    property var notifications
    property bool wifiOn: true
    property string ssid: ""
    property real brightness: 0.6
    readonly property bool nightShift: Prefs.nightShift
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var player: Mpris.players.values.length ? Mpris.players.values[0] : null

    function toggle() { open = !open; if (open) refresh() }

    // A module opens into its detail view in place, as on the Mac: the Wi-Fi
    // networks, the paired Bluetooth devices, the sound outputs.
    property string detail: ""          // "" | "wifi" | "bluetooth" | "sound" | "mirroring"
    property var networks: []           // [{ ssid, signal, secure, active }]
    function showDetail(kind) {
        // Anything else (asked over IPC) had an empty "No Outputs" panel.
        if (!["", "wifi", "bluetooth", "sound", "mirroring"].includes(kind)) return
        detail = kind
        // Keep the last networks on screen while rescanning, so the list
        // doesn't collapse and regrow under the pointer.
        if (kind === "wifi") scanProc.running = true
        if (kind === "mirroring") { airplayProbe.running = true; if (!castBrowse.running) castBrowse.running = true }
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
        brightProc.running = true
    }

    visible: open || closeTimer.running
    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    implicitWidth: 356
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

    onOpenChanged: if (!open) { closeTimer.restart(); detail = ""; editing = false }
    Timer { id: closeTimer; interval: 180 }
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
                const bits = line.split(",")
                if (bits.length > 3) cc.brightness = parseInt(bits[3]) / 100
            }
        }
    }

    // ---------------------------------------------------------- the grid
    // As in Big Sur: one panel of glass holding the controls, each a tile a
    // shade lighter than the glass around it, on a four-column grid. Wi-Fi,
    // Bluetooth and AirDrop share a tile; Focus and two toggles sit beside
    // it; then the small toggles, Display, Sound and what's playing.
    readonly property real unit: 68
    readonly property real gap: 12
    function span(n) { return n * unit + (n - 1) * gap }
    // Control Center is a fixed grid of modules, as on the Mac: its text
    // follows Text Size only a little (up to 115%), so labels never crowd
    // the controls beside them.
    function cs(n) { return Math.round(n * Math.max(1, Math.min(1.15, Theme.textScale))) }

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

    // A tile on the panel: a rounded rectangle a shade lighter than the glass,
    // lighter still under the pointer, giving a little when pressed.
    component Module: Rectangle {
        id: mod
        property bool pressed: false
        property bool hovered: false
        property bool bare: false              // a row inside a shared tile
        radius: 14
        color: bare ? (pressed ? (Theme.dark ? "#1affffff" : "#14000000") : "transparent")
            : Theme.dark ? Qt.rgba(1, 1, 1, pressed ? 0.17 : hovered ? 0.13 : 0.09)
                         : Qt.rgba(1, 1, 1, pressed ? 0.38 : hovered ? 0.72 : 0.56)
        border { width: bare ? 0 : 0.5; color: Theme.dark ? "#1fffffff" : "#12000000" }
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: pressed && !Prefs.reduceMotion ? Math.max(0.95, 1 - 4 / Math.max(1, Math.max(width, height))) : 1
        Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: mod.pressed ? Theme.snappy : Theme.bouncy } }
    }

    // A glyph that pops when its control switches, as SF Symbols bounce.
    component PopSymbol: Symbol {
        id: glyph
        property bool on: false
        property real pop: 1
        onOnChanged: if (!Prefs.reduceMotion) popAnim.restart()
        transform: Scale { origin.x: glyph.width / 2; origin.y: glyph.height / 2; xScale: glyph.pop; yScale: glyph.pop }
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: glyph; property: "pop"; to: 1.22; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: glyph; property: "pop"; to: 1; duration: 365; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
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
        signal activated()
        width: cc.span(2); height: cc.unit
        pressed: capTap.pressed
        hovered: capTap.containsMouse
        IconDisc { id: capDisc; x: capsule.bare ? 8 : 11; anchors.verticalCenter: parent.verticalCenter; icon: capsule.icon; on: capsule.on; size: capsule.bare ? 34 : 42 }
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
                font { family: Theme.fontUi; pixelSize: cc.cs(13); weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: !!capsule.subtitle
                text: capsule.subtitle
                color: Theme.secondaryLabel
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: cc.cs(11) }
            }
        }
        MouseArea {
            id: capTap
            anchors.fill: parent
            hoverEnabled: true
            onClicked: (m) => {
                const onDisc = m.x < capDisc.x + capDisc.width + 4
                if (onDisc && capsule.toggleAction) capsule.toggleAction()
                else capsule.activated()
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: capsule.title
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
        width: parent.width; height: subtitle ? 44 : 34; radius: 9
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
    // One toggle, one square tile: its disc fills (white over dark glass, the
    // accent in light mode) while it's on, and its name is under it.
    component Circle: Module {
        id: circle
        property string icon
        property string name
        property bool on: false
        property string badge: ""            // Edit Controls: "+" or "−"
        signal activated()
        width: cc.unit; height: cc.unit
        pressed: circleTap.pressed
        hovered: circleTap.containsMouse
        Rectangle {
            id: circleDisc
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
            width: 32; height: 32; radius: 16
            color: Theme.dark ? "#2effffff" : "#17000000"
            // On, the fill grows out from the middle on a spring.
            Rectangle {
                objectName: "circleFill"
                anchors.fill: parent
                radius: width / 2
                color: Theme.dark ? "#ffffff" : Theme.accent
                opacity: circle.on ? 1 : 0
                scale: circle.on || Prefs.reduceMotion ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 140 } }
                Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.bouncy } }
            }
            PopSymbol {
                anchors.centerIn: parent
                name: circle.icon; size: 16
                on: circle.on
                tone: circle.on ? (Theme.dark ? "dark" : "white") : "auto"
            }
        }
        Text {
            anchors { top: circleDisc.bottom; topMargin: 3; left: parent.left; right: parent.right; leftMargin: 3; rightMargin: 3 }
            horizontalAlignment: Text.AlignHCenter
            text: circle.name
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.9
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: cc.cs(9); weight: Font.Medium }
        }
        Rectangle {
            visible: !!circle.badge
            x: -4; y: -4
            width: 20; height: 20; radius: 10
            color: Theme.dark ? "#5a5a5e" : "#8e8e93"
            border { width: 1.5; color: Theme.dark ? "#1c1c1e" : "#ffffff" }
            Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: circle.badge; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: cc.cs(14); weight: Font.Bold } }
        }
        MouseArea {
            id: circleTap
            anchors.fill: parent
            hoverEnabled: true
            onClicked: circle.activated()
        }
        Accessible.role: Accessible.Button
        Accessible.name: circle.name
    }

    // Display and Sound: a wide tile, its name, and a thin slider between a
    // small and a large glyph; the track thickens while you drag it.
    component SliderTile: Module {
        id: tile
        property string title
        property string lowIcon
        property string highIcon
        property real value: 0.5
        property bool expandable: false      // Sound: its outputs, from the AirPlay button
        signal moved(real value)
        signal expand()
        width: cc.span(4); height: cc.unit + 6
        function setFromX(x) { if (track.width > 0) moved(Math.max(0, Math.min(1, x / track.width))) }
        Text {
            anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 11 }
            text: tile.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: cc.cs(13); weight: Font.DemiBold }
        }
        Symbol {
            id: low
            anchors { left: parent.left; leftMargin: 16; verticalCenter: track.verticalCenter }
            name: tile.lowIcon; size: 14; tone: "auto"
        }
        Item {
            id: track
            anchors { left: low.right; leftMargin: 10; right: high.left; rightMargin: 10; bottom: parent.bottom; bottomMargin: 19 }
            height: drag.pressed ? 10 : 6
            Behavior on height { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 120; easing.type: Easing.OutCubic } }
            readonly property real level: Math.max(0, Math.min(1, tile.value))
            Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.dark ? "#3dffffff" : "#1f000000" }
            // White over dark glass; in light mode a dark fill, since white
            // disappears against the light glass.
            Rectangle {
                width: Math.max(parent.height, parent.width * track.level); height: parent.height
                radius: height / 2
                color: Theme.dark ? "#ffffff" : "#d93a3a3c"
                Behavior on width { enabled: !drag.pressed && !Prefs.reduceMotion; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: drag
                anchors { fill: parent; topMargin: -14; bottomMargin: -14 }
                onPressed: (m) => tile.setFromX(m.x)
                onPositionChanged: (m) => { if (pressed) tile.setFromX(m.x) }
            }
            Accessible.role: Accessible.Slider
            Accessible.name: tile.title
        }
        Symbol {
            id: high
            anchors { right: outputs.visible ? outputs.left : parent.right; rightMargin: outputs.visible ? 10 : 16; verticalCenter: track.verticalCenter }
            name: tile.highIcon; size: 17; tone: "auto"
        }
        Rectangle {
            id: outputs
            visible: tile.expandable
            anchors { right: parent.right; rightMargin: 12; verticalCenter: track.verticalCenter }
            width: 32; height: 32; radius: 16
            color: outArea.pressed ? (Theme.dark ? "#4dffffff" : "#33000000") : (Theme.dark ? "#2effffff" : "#17000000")
            Symbol { anchors.centerIn: parent; name: "airplay"; size: 15; tone: "auto" }
            MouseArea { id: outArea; anchors.fill: parent; onClicked: tile.expand() }
            Accessible.role: Accessible.Button
            Accessible.name: tile.title + " Output"
        }
    }

    // The panel: one piece of glass behind every control, as in Big Sur.
    // HyprGlass makes glass of anything on this surface more than 25% opaque
    // (namespace_mask_thresholds in hyprglass-sync.sh); both tints stay well
    // above that, so the backdrop is blurred behind the whole panel.
    Item {
        id: panel
        anchors { top: parent.top; right: parent.right; topMargin: 24 }
        width: cc.span(4) + 28
        height: (cc.detail ? detailView.implicitHeight : content.implicitHeight) + 28
        Behavior on height { enabled: !Prefs.reduceMotion; Spring { spring: Theme.snappy } }
        opacity: cc.open ? 1 : 0
        scale: cc.open || Prefs.reduceMotion ? 1 : 0.965
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Glass {
            objectName: "ccPanel"
            anchors.fill: parent
            radius: 22
            tint: Theme.dark ? Qt.rgba(0.13, 0.13, 0.15, 0.5) : Qt.rgba(0.94, 0.94, 0.96, 0.5)
        }
    }

    // The grid and a module's detail view share the panel: the grid slides
    // out to the left as the detail slides in from the right.
    Item {
    id: stage
    z: 2
    anchors.fill: panel
    clip: true
    scale: panel.scale
    transformOrigin: Item.TopRight

    Column {
        id: content
        x: 14; y: 14
        width: cc.span(4)
        spacing: cc.gap
        opacity: cc.detail ? 0 : panel.opacity
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 160; easing.type: Easing.OutCubic } }
        transform: Translate {
            x: cc.detail && !Prefs.reduceMotion ? -28 : 0
            Behavior on x { NumberAnimation { duration: 225; easing.type: Easing.OutCubic } }
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

        // Wi-Fi, Bluetooth and AirDrop in one tile | Focus, Dark Mode, Night Shift
        Row {
            spacing: cc.gap
            Module {
                objectName: "ccConnectivity"
                width: cc.span(2); height: cc.span(2)
                Column {
                    anchors { fill: parent; margins: 4 }
                    Capsule {
                        bare: true
                        width: parent.width; height: parent.height / 3
                        icon: "wifi"; title: "Wi-Fi"
                        subtitle: cc.wifiOn ? (cc.ssid || "Not Connected") : "Off"
                        on: cc.wifiOn
                        toggleAction: () => {
                            cc.wifiOn = !cc.wifiOn
                            Quickshell.execDetached(["nmcli", "radio", "wifi", cc.wifiOn ? "on" : "off"])
                        }
                        onActivated: cc.showDetail("wifi")
                    }
                    Capsule {
                        bare: true
                        width: parent.width; height: parent.height / 3
                        icon: "bluetooth"; title: "Bluetooth"
                        subtitle: Bluetooth.defaultAdapter?.enabled ? "On" : "Off"
                        on: Bluetooth.defaultAdapter?.enabled ?? false
                        toggleAction: () => Quickshell.execDetached(["bluetoothctl", "power", (Bluetooth.defaultAdapter?.enabled ?? false) ? "off" : "on"])
                        onActivated: cc.showDetail("bluetooth")
                    }
                    Capsule {
                        bare: true
                        width: parent.width; height: parent.height / 3
                        icon: "broadcast"; title: "AirDrop"
                        subtitle: cc.airdropOn ? "Everyone" : "Receiving Off"
                        on: cc.airdropOn
                        toggleAction: () => {
                            cc.airdropOn = !cc.airdropOn
                            Quickshell.execDetached(["gg-airdrop", "--set", cc.airdropOn ? "everyone" : "off"])
                        }
                        onActivated: { cc.open = false; Quickshell.execDetached(["gg-airdrop"]) }
                    }
                }
            }
            Column {
                spacing: cc.gap
                Capsule {
                    icon: "moon"; title: "Focus"; subtitle: cc.notifications?.dnd ? "Do Not Disturb" : ""
                    on: cc.notifications?.dnd ?? false
                    onActivated: Quickshell.execDetached(["gg-pref", "focus.dnd", (cc.notifications?.dnd ?? false) ? "false" : "true"])
                }
                Row {
                    spacing: cc.gap
                    Circle {
                        icon: "contrast"; name: "Dark Mode"; on: Theme.dark
                        onActivated: {
                            Theme.dark = !Theme.dark
                            cc.run("gsettings set org.gnome.desktop.interface color-scheme " + (Theme.dark ? "prefer-dark" : "default"))
                            Quickshell.execDetached(["sh", "-c",
                                "d=$HOME/.config/golden-gate; mkdir -p \"$d\"; printf '{ \"mode\": \"%s\" }\\n' \"$1\" > \"$d/appearance.json\"",
                                "sh", Theme.dark ? "dark" : "light"])
                        }
                    }
                    Circle {
                        icon: "sun"; name: "Night Shift"; on: cc.nightShift
                        onActivated: {
                            const enabled = !cc.nightShift
                            Quickshell.execDetached(["gg-pref", "display.nightShift", enabled ? "true" : "false"])
                            cc.run(enabled ? "hyprsunset -t " + Prefs.displayWarmth : "pkill -x hyprsunset")
                        }
                    }
                }
            }
        }

        // The small toggles, four to a row: Mission Control, Screen Mirroring
        // and the controls you've added (Edit Controls).
        Grid {
            columns: 4
            spacing: cc.gap
            Circle { icon: "stage"; name: "Mission Control"; onActivated: cc.ipc("missioncontrol toggle") }
            Circle { icon: "mirror"; name: cc.mirroring ? (cc.airplay.device || "Mirroring") : "Screen Mirroring"; on: cc.airplayOn; onActivated: cc.showDetail("mirroring") }
            Repeater {
                model: cc.extras
                Circle {
                    required property var modelData
                    icon: modelData.icon; name: modelData.name
                    badge: cc.editing ? "−" : ""
                    onActivated: cc.editing ? cc.toggleExtra(modelData.id) : modelData.run()
                }
            }
        }

        SliderTile {
            title: "Display"; lowIcon: "sun"; highIcon: "sun-max"; value: cc.brightness
            onMoved: (value) => {
                cc.brightness = value
                cc.run("brightnessctl -q set " + Math.round(Math.max(0.02, value) * 100) + "%")
                Quickshell.execDetached(["gg-pref", "display.brightness", String(value)])
            }
        }
        SliderTile {
            title: "Sound"; lowIcon: "speaker"; highIcon: "speaker-wave"
            expandable: true
            onExpand: cc.showDetail("sound")
            value: cc.sink?.audio?.volume ?? 0
            onMoved: (value) => { if (cc.sink?.audio) cc.sink.audio.volume = value }
        }

        // What's playing, across the panel.
        Module {
            id: nowPlaying
            width: cc.span(4); height: cc.unit
            Rectangle {
                id: art
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44; radius: 9
                clip: true
                color: "#7c7ce7"
                Image { anchors.fill: parent; source: cc.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                Symbol { anchors.centerIn: parent; visible: !(cc.player?.trackArtUrl); name: "music"; size: 22; tone: "white" }
            }
            Column {
                anchors { left: art.right; right: media.left; leftMargin: 10; rightMargin: 6; verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width
                    text: cc.player?.trackTitle || "Not Playing"
                    color: Theme.label
                    elide: Text.ElideRight
                    font { family: Theme.fontUi; pixelSize: cc.cs(13); weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    text: cc.player ? [cc.player.trackArtist, cc.player.trackAlbum].filter((x) => !!x).join(" – ") || cc.player.identity : "Music"
                    color: Theme.secondaryLabel
                    elide: Text.ElideRight
                    font { family: Theme.fontUi; pixelSize: cc.cs(11) }
                }
            }
            Row {
                id: media
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                Repeater {
                    model: [
                        ["backward", () => cc.player?.previous(), 18],
                        [cc.player?.isPlaying ? "pause" : "play", () => cc.player ? cc.player.togglePlaying() : cc.launch("org.goldengate.Music"), 22],
                        ["forward", () => cc.player?.next(), 18]
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 34; height: 34; radius: 17
                        color: mediaArea.pressed ? (Theme.dark ? "#33ffffff" : "#1f000000") : mediaArea.containsMouse ? (Theme.dark ? "#1affffff" : "#0f000000") : "transparent"
                        Symbol { anchors.centerIn: parent; name: modelData[0]; size: modelData[2]; tone: "auto" }
                        MouseArea { id: mediaArea; anchors.fill: parent; hoverEnabled: true; onClicked: modelData[1]() }
                    }
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
                anchors.centerIn: parent
                width: editLabel.implicitWidth + 30; height: 30
                radius: 15
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
        transform: Translate { x: detailShift.x }
    }

    // The detail view of one module, in the same panel.
    ColumnLayout {
        id: detailView
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 20; leftMargin: 22; rightMargin: 22 }
        spacing: 2
        opacity: cc.detail ? panel.opacity : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 180; easing.type: Easing.OutCubic } }
        transform: Translate {
            id: detailShift
            x: cc.detail || Prefs.reduceMotion ? 0 : 28
            Behavior on x { NumberAnimation { duration: 225; easing.type: Easing.OutCubic } }
        }
        focus: cc.detail !== ""
        Keys.onEscapePressed: cc.detail = ""

        readonly property string title: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", sound: "Sound Output", mirroring: "Screen Mirroring" })[cc.detail] ?? ""
        readonly property bool hasSwitch: cc.detail === "wifi" || cc.detail === "bluetooth"
        readonly property bool on: cc.detail === "wifi" ? cc.wifiOn : (Bluetooth.defaultAdapter?.enabled ?? false)

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2; Layout.rightMargin: 4
            Layout.preferredHeight: 34
            spacing: 6
            Rectangle {
                width: 24; height: 24; radius: 12
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

        Text {
            visible: rows.count === 0 && cc.detail !== "mirroring"
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
                Layout.preferredHeight: 34
                radius: 9
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
            radius: 9
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
                onClicked: {
                    const pane = ({ wifi: "wifi", bluetooth: "bluetooth", sound: "sound", mirroring: "airplay" })[cc.detail]
                    cc.open = false
                    cc.run("gg-settings " + pane)
                }
            }
        }
    }
    }
}
