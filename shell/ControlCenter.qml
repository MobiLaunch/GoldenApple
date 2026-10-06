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
    property string detail: ""          // "" | "wifi" | "bluetooth" | "sound"
    property var networks: []           // [{ ssid, signal, secure, active }]
    function showDetail(kind) {
        detail = kind
        // Keep the last networks on screen while rescanning, so the list
        // doesn't collapse and regrow under the pointer.
        if (kind === "wifi") scanProc.running = true
        if (kind === "mirroring") airplayProbe.running = true
    }
    // AirPlay Receiver: the gg-airplay user service (UxPlay) lets an iPhone,
    // iPad or Mac mirror to this computer.
    property bool airplayOn: false
    function setAirplay(on) {
        airplayOn = on
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "gg-airplay.service"])
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
    // As in macOS 26: no container, every control its own piece of glass on a
    // four-column grid — capsules (Wi-Fi, Bluetooth, AirDrop, Focus), circles
    // (one toggle each), a square for what's playing, wide tiles for the
    // sliders — floating over the blurred desktop.
    readonly property real unit: 68
    readonly property real gap: 12
    function span(n) { return n * unit + (n - 1) * gap }

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

    // A piece of the grid: glass, round at the ends.
    component Module: Glass {
        radius: Math.min(width, height) / 2
        tint: Theme.dark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.6)
    }

    // The round icon at the start of a capsule: blue while it's on.
    component IconDisc: Rectangle {
        id: disc
        property string icon
        property bool on: false
        width: 42; height: 42; radius: 21
        color: on ? Theme.accent : (Theme.dark ? "#2effffff" : "#17000000")
        Behavior on color { ColorAnimation { duration: Prefs.reduceMotion ? 1 : 140 } }
        Symbol { anchors.centerIn: parent; name: disc.icon; size: 19; tone: disc.on ? "white" : "auto" }
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
        IconDisc { id: capDisc; x: 13; anchors.verticalCenter: parent.verticalCenter; icon: capsule.icon; on: capsule.on }
        Column {
            anchors { left: capDisc.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width
                text: capsule.title
                color: Theme.label
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                visible: !!capsule.subtitle
                text: capsule.subtitle
                color: Theme.secondaryLabel
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: 11 }
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

    // One toggle, one circle: white while it's on (the accent in light mode),
    // and its name above it while the pointer rests on it.
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
            anchors.fill: parent
            radius: width / 2
            color: Theme.dark ? "#ffffff" : Theme.accent
            opacity: circle.on ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 140 } }
        }
        Symbol {
            anchors.centerIn: parent
            name: circle.icon; size: 22
            tone: circle.on ? (Theme.dark ? "dark" : "white") : "auto"
        }
        Rectangle {
            visible: !!circle.badge
            x: -2; y: -2
            width: 22; height: 22; radius: 11
            color: Theme.dark ? "#5a5a5e" : "#8e8e93"
            border { width: 1.5; color: Theme.dark ? "#1c1c1e" : "#ffffff" }
            Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: circle.badge; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold } }
        }
        property bool showHint: false
        MouseArea {
            id: circleTap
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { circle.showHint = false; circle.activated() }
            onContainsMouseChanged: { circle.showHint = false; if (containsMouse) hint.restart(); else hint.stop() }
        }
        Timer { id: hint; interval: 650; onTriggered: circle.showHint = true }
        Rectangle {
            visible: circle.showHint && !!circle.name && !cc.editing
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 6 }
            width: hintText.implicitWidth + 14; height: 22; radius: 11
            color: Theme.dark ? "#e62c2c2e" : "#f2ffffff"
            border { width: 0.5; color: Theme.separator }
            z: 10
            Text { id: hintText; anchors.centerIn: parent; text: circle.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 11 } }
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
        radius: 30
        function setFromX(x) { if (track.width > 0) moved(Math.max(0, Math.min(1, x / track.width))) }
        Text {
            anchors { left: parent.left; leftMargin: 18; top: parent.top; topMargin: 11 }
            text: tile.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
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

    // No card behind the controls: the controls are the glass. HyprGlass makes
    // glass of anything on this surface more than 8% opaque
    // (namespace_mask_thresholds in hyprglass-sync.sh), so the panel itself
    // is only geometry, and what's behind the controls is a soft shadow kept
    // under that line: a slight darkening, never a card.
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
        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        // The shadow: darkest in the middle, fading out past the edges, and
        // never above 6%.
        Repeater {
            model: 6
            Rectangle {
                required property int index
                anchors { fill: parent; margins: 18 - index * 6 }
                radius: 40 + index * 6
                color: "#000000"
                opacity: Theme.dark ? 0.012 : 0.007
            }
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
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        // In use: which apps have the microphone, camera, screen or location,
        // each with its indicator's colour, as at the top of the Mac's.
        Module {
            visible: Privacy.any
            width: cc.span(4)
            height: inUse.implicitHeight + 22
            radius: 22
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
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                        }
                        Text {
                            text: Privacy[parent.modelData].join(", ")
                            color: Theme.secondaryLabel
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, cc.span(4) - 150)
                            font { family: Theme.fontUi; pixelSize: 12 }
                        }
                    }
                }
            }
        }

        // Wi-Fi and Bluetooth | what's playing
        Row {
            spacing: cc.gap
            Column {
                spacing: cc.gap
                Capsule {
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
                    icon: "bluetooth"; title: "Bluetooth"
                    subtitle: Bluetooth.defaultAdapter?.enabled ? "On" : "Off"
                    on: Bluetooth.defaultAdapter?.enabled ?? false
                    toggleAction: () => Quickshell.execDetached(["bluetoothctl", "power", (Bluetooth.defaultAdapter?.enabled ?? false) ? "off" : "on"])
                    onActivated: cc.showDetail("bluetooth")
                }
            }
            Module {
                id: nowPlaying
                width: cc.span(2); height: cc.span(2)
                radius: 32
                Rectangle {
                    id: art
                    x: 16; y: 16
                    width: 44; height: 44; radius: 9
                    clip: true
                    color: "#7c7ce7"
                    Image { anchors.fill: parent; source: cc.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    Symbol { anchors.centerIn: parent; visible: !(cc.player?.trackArtUrl); name: "music"; size: 22; tone: "white" }
                }
                Column {
                    anchors { left: parent.left; right: parent.right; top: art.bottom; leftMargin: 16; rightMargin: 14; topMargin: 8 }
                    Text {
                        width: parent.width
                        text: cc.player?.trackTitle || "Not Playing"
                        color: Theme.label
                        elide: Text.ElideRight
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        text: cc.player ? [cc.player.trackArtist, cc.player.trackAlbum].filter((x) => !!x).join(" – ") || cc.player.identity : "Music"
                        color: Theme.secondaryLabel
                        elide: Text.ElideRight
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                    spacing: 6
                    Repeater {
                        model: [
                            ["backward", () => cc.player?.previous(), 20],
                            [cc.player?.isPlaying ? "pause" : "play", () => cc.player ? cc.player.togglePlaying() : cc.launch("org.goldengate.Music"), 24],
                            ["forward", () => cc.player?.next(), 20]
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 38; height: 34; radius: 17
                            color: mediaArea.pressed ? (Theme.dark ? "#33ffffff" : "#1f000000") : mediaArea.containsMouse ? (Theme.dark ? "#1affffff" : "#0f000000") : "transparent"
                            Symbol { anchors.centerIn: parent; name: modelData[0]; size: modelData[2]; tone: "auto" }
                            MouseArea { id: mediaArea; anchors.fill: parent; hoverEnabled: true; onClicked: modelData[1]() }
                        }
                    }
                }
            }
        }

        // AirDrop | Mission Control | Screen Mirroring
        Row {
            spacing: cc.gap
            Capsule {
                icon: "broadcast"; title: "AirDrop"
                subtitle: cc.airdropOn ? "Everyone" : "Receiving Off"
                on: cc.airdropOn
                toggleAction: () => {
                    cc.airdropOn = !cc.airdropOn
                    Quickshell.execDetached(["gg-airdrop", "--set", cc.airdropOn ? "everyone" : "off"])
                }
                onActivated: { cc.open = false; Quickshell.execDetached(["gg-airdrop"]) }
            }
            Circle { icon: "stage"; name: "Mission Control"; onActivated: cc.ipc("missioncontrol toggle") }
            Circle { icon: "mirror"; name: "Screen Mirroring"; on: cc.airplayOn; onActivated: cc.showDetail("mirroring") }
        }

        // Appearance | Night Shift | Focus
        Row {
            spacing: cc.gap
            Circle {
                icon: "contrast"; name: Theme.dark ? "Dark Mode" : "Light Mode"; on: Theme.dark
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
            Capsule {
                icon: "moon"; title: "Focus"; subtitle: cc.notifications?.dnd ? "Do Not Disturb" : ""
                on: cc.notifications?.dnd ?? false
                onActivated: Quickshell.execDetached(["gg-pref", "focus.dnd", (cc.notifications?.dnd ?? false) ? "false" : "true"])
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

        // The controls you've added (Edit Controls), four to a row.
        Grid {
            visible: cc.extras.length > 0
            columns: 4
            spacing: cc.gap
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

        // Edit Controls: the ones you can add, with a + each.
        Column {
            visible: cc.editing
            width: parent.width
            spacing: 8
            Text { text: "Add Controls"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
            Grid {
                columns: 4
                spacing: cc.gap
                Repeater {
                    model: cc.extraCatalog.filter((e) => !cc.extras.some((x) => x.id === e.id))
                    Column {
                        required property var modelData
                        spacing: 4
                        Circle { icon: modelData.icon; name: modelData.name; badge: "+"; onActivated: cc.toggleExtra(modelData.id) }
                        Text {
                            width: cc.unit
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.name
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 10 }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width; height: 32
            Module {
                anchors.centerIn: parent
                width: editLabel.implicitWidth + 30; height: 30
                pressed: editTap.pressed
                hovered: editTap.containsMouse
                Text { id: editLabel; anchors.centerIn: parent; text: cc.editing ? "Done" : "Edit Controls"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                MouseArea { id: editTap; anchors.fill: parent; hoverEnabled: true; onClicked: cc.editing = !cc.editing }
            }
        }
    }

    // The detail view's card, the same fill as the grid's modules; it follows
    // the view as it slides and fades.
    Module {
        x: detailView.x - 8; y: detailView.y - 6
        width: detailView.width + 16; height: detailView.height + 12
        radius: 28
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
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
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
                font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
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

        // Screen Mirroring: this computer as an AirPlay receiver, and mirroring
        // it to a Miracast or Chromecast TV.
        Column {
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
                    Text { text: "AirPlay Receiver"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                    Text {
                        width: parent.width
                        text: "Mirror your iPhone or iPad here"
                        elide: Text.ElideRight
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                }
                Shared.Switch {
                    id: airplaySwitch
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    checked: cc.airplayOn
                    onToggled: cc.setAirplay(!cc.airplayOn)
                }
            }
            Rectangle {
                width: parent.width; height: 34; radius: 9
                color: tvArea.pressed ? Theme.selection : tvArea.containsMouse ? Theme.menuHighlight : "transparent"
                Row {
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 9
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: Theme.dark ? "#26ffffff" : "#14000000"
                        Symbol { anchors.centerIn: parent; name: "mirror"; size: 13; tone: "auto" }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Mirror to a TV or Display…"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                }
                MouseArea {
                    id: tvArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { cc.open = false; cc.run("gnome-network-displays") }
                }
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
            font { family: Theme.fontUi; pixelSize: 12 }
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
                        font { family: Theme.fontUi; pixelSize: 13; weight: item.active ? Font.DemiBold : Font.Normal }
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
                text: cc.detail === "mirroring" ? "Display Settings…" : detailView.title.replace(" Output", "") + " Settings…"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13 }
            }
            MouseArea {
                id: settingsArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    const pane = ({ wifi: "wifi", bluetooth: "bluetooth", sound: "sound", mirroring: "displays" })[cc.detail]
                    cc.open = false
                    cc.run("gg-settings " + pane)
                }
            }
        }
    }
    }
}
