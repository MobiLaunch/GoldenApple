// Big Sur-inspired Control Center: one readable translucent panel with grouped
// connectivity, Focus/display controls, brightness/sound and media.
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
    implicitHeight: Math.min(760, (screen ? screen.height : 800) - 16)
    mask: Region { item: panel }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-controlcenter"
    WlrLayershell.layer: WlrLayer.Overlay

    onOpenChanged: if (!open) { closeTimer.restart(); detail = "" }
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

    component GroupCard: Rectangle {
        id: card
        property bool pressed: false
        // A module is a fill on the panel's glass, not glass on glass; its
        // corners are concentric with the panel's (25 - 12 padding ≈ 17).
        radius: 17
        color: Theme.dark ? "#1affffff" : "#8cffffff"
        border { width: 0.5; color: Theme.dark ? "#1affffff" : "#0f000000" }
        scale: pressed && !Prefs.reduceMotion ? 0.985 : 1
        Behavior on scale { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 85; easing.type: Easing.OutCubic } }
    }

    component RoundToggle: Rectangle {
        id: toggle
        property string icon
        property bool on: false
        signal activated()
        width: 38; height: 38; radius: 19
        color: on ? Theme.accent : (Theme.dark ? "#28ffffff" : "#16000000")
        border { width: on ? 0 : 0.5; color: Theme.dark ? "#24ffffff" : "#13000000" }
        scale: area.pressed && !Prefs.reduceMotion ? 0.91 : area.containsMouse && !Prefs.reduceMotion ? 1.035 : 1
        Behavior on scale { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 80; easing.type: Easing.OutCubic } }
        Symbol { anchors.centerIn: parent; name: toggle.icon; size: 19; tone: toggle.on ? "white" : "auto" }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: toggle.activated() }
    }

    component ConnectivityRow: Item {
        id: row
        property string icon
        property string title
        property string subtitle
        property bool on: false
        property var toggleAction: null
        signal activated()
        implicitHeight: 48

        RoundToggle {
            id: connectivityToggle
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            icon: row.icon
            on: row.on
            onActivated: {
                if (row.toggleAction) row.toggleAction()
                else row.activated()
            }
        }
        Column {
            anchors {
                left: connectivityToggle.right; leftMargin: 10
                right: chevron.left; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 0
            Text {
                width: parent.width
                text: row.title
                color: Theme.label
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                text: row.subtitle
                color: Theme.secondaryLabel
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: 10 }
            }
        }
        Symbol {
            id: chevron
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            name: "chevron-right"
            size: 11
            tone: "gray"
        }
        MouseArea {
            anchors { left: connectivityToggle.right; right: parent.right; top: parent.top; bottom: parent.bottom }
            hoverEnabled: true
            onClicked: row.activated()
        }
    }

    component ActionTile: GroupCard {
        id: tile
        property string icon
        property string title
        property string subtitle
        property bool on: false
        signal activated()
        implicitHeight: 78
        pressed: tap.pressed

        RoundToggle {
            anchors { left: parent.left; leftMargin: 11; top: parent.top; topMargin: 10 }
            width: 30; height: 30; radius: 15
            icon: tile.icon
            on: tile.on
            onActivated: tile.activated()
        }
        Text {
            anchors { left: parent.left; leftMargin: 11; right: parent.right; rightMargin: 8; bottom: subtitleText.visible ? subtitleText.top : parent.bottom; bottomMargin: subtitleText.visible ? 1 : 9 }
            text: tile.title
            color: Theme.label
            elide: Text.ElideRight
            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
        }
        Text {
            id: subtitleText
            visible: tile.subtitle !== ""
            anchors { left: parent.left; leftMargin: 11; right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 8 }
            text: tile.subtitle
            color: Theme.secondaryLabel
            elide: Text.ElideRight
            font { family: Theme.fontUi; pixelSize: 9 }
        }
        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: tile.activated() }
    }

    component BigSurSlider: GroupCard {
        id: slider
        property string title
        property string lowIcon
        property string highIcon
        property real value: 0.5
        property bool expandable: false     // a button to the module's detail view
        signal moved(real value)
        signal expand()
        implicitHeight: 72

        function setFromX(x) {
            if (track.width <= 0) return
            moved(Math.max(0, Math.min(1, x / track.width)))
        }

        Text {
            anchors { left: parent.left; leftMargin: 13; top: parent.top; topMargin: 9 }
            text: slider.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
        }
        // Sound's button to its output list: a round glass-fill button, as on the Mac.
        Rectangle {
            visible: slider.expandable
            anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 7 }
            width: 22; height: 22; radius: 11
            color: expandArea.pressed ? Theme.selection : expandArea.containsMouse ? (Theme.dark ? "#33ffffff" : "#1f000000") : Theme.fill
            Symbol { anchors.centerIn: parent; name: "chevron-right"; size: 9; tone: "auto"; opacity: 0.7 }
            MouseArea { id: expandArea; anchors.fill: parent; hoverEnabled: true; onClicked: slider.expand() }
            Accessible.role: Accessible.Button
            Accessible.name: slider.title + " Output"
        }
        // A thick capsule, filled white up to the value, with the low glyph
        // inside the fill and the fill's end as the knob (macOS Control Center).
        Item {
            id: track
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
            height: 22
            readonly property real level: Math.max(0, Math.min(1, slider.value))
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.dark ? "#2effffff" : "#1f000000"
            }
            Rectangle {
                id: fill
                height: parent.height
                width: Math.max(height, parent.width * track.level)
                radius: height / 2
                color: "#ffffff"
                border { width: Theme.dark ? 0 : 0.5; color: "#1f000000" }
                Behavior on width { enabled: !drag.pressed && !Prefs.reduceMotion; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
            // The knob: the fill's round end, lifted a little.
            Rectangle {
                width: parent.height; height: parent.height; radius: height / 2
                x: fill.width - width
                color: "#ffffff"
                border { width: 0.5; color: "#33000000" }
                scale: drag.pressed && !Prefs.reduceMotion ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
            }
            Symbol {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                name: slider.lowIcon; size: 12; tone: "dark"; opacity: 0.55
            }
            MouseArea {
                id: drag
                anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
                hoverEnabled: true
                onPressed: mouse => slider.setFromX(mouse.x)
                onPositionChanged: mouse => { if (pressed) slider.setFromX(mouse.x) }
            }
        }
    }

    // The Dock's glass: smoked and clear enough to show the blurred desktop,
    // where the regular panel material read as frosted milk. Everything with
    // text sits on a module card, so it stays legible over any wallpaper.
    Glass {
        id: panel
        role: "dock"
        anchors { top: parent.top; right: parent.right; topMargin: 24 }
        width: 344
        height: (cc.detail ? detailView.implicitHeight : content.implicitHeight) + 24
        Behavior on height { enabled: !Prefs.reduceMotion; Spring { spring: Theme.snappy } }
        radius: 25
        opacity: cc.open ? 1 : 0
        scale: cc.open || Prefs.reduceMotion ? 1 : 0.965
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    }

    // The module grid and a module's detail view share the panel: the grid
    // slides out to the left as the detail slides in from the right, both
    // clipped to the glass while its height follows.
    Item {
    id: stage
    z: 2
    anchors.fill: panel
    clip: true
    scale: panel.scale
    transformOrigin: Item.TopRight

    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 12; leftMargin: 12; rightMargin: 12 }
        spacing: 9
        opacity: cc.detail ? 0 : panel.opacity
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 160; easing.type: Easing.OutCubic } }
        transform: Translate {
            x: cc.detail && !Prefs.reduceMotion ? -28 : 0
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 9

            GroupCard {
                Layout.fillWidth: true
                Layout.minimumWidth: 160
                Layout.preferredHeight: 164
                Column {
                    anchors { fill: parent; margins: 11 }
                    spacing: 1
                    ConnectivityRow {
                        width: parent.width
                        icon: "wifi"; title: "Wi-Fi"
                        subtitle: cc.wifiOn ? (cc.ssid || "Not Connected") : "Off"
                        on: cc.wifiOn
                        toggleAction: () => {
                            cc.wifiOn = !cc.wifiOn
                            Quickshell.execDetached(["nmcli", "radio", "wifi", cc.wifiOn ? "on" : "off"])
                        }
                        onActivated: cc.showDetail("wifi")
                    }
                    Rectangle { width: parent.width - 48; x: 48; height: 0.5; color: Theme.separator }
                    ConnectivityRow {
                        width: parent.width
                        icon: "bluetooth"; title: "Bluetooth"
                        subtitle: Bluetooth.defaultAdapter?.enabled ? "On" : "Off"
                        on: Bluetooth.defaultAdapter?.enabled ?? false
                        toggleAction: () => {
                            const enabled = !(Bluetooth.defaultAdapter?.enabled ?? false)
                            Quickshell.execDetached(["bluetoothctl", "power", enabled ? "on" : "off"])
                        }
                        onActivated: cc.showDetail("bluetooth")
                    }
                    Rectangle { width: parent.width - 48; x: 48; height: 0.5; color: Theme.separator }
                    // AirDrop: the circle turns receiving on and off; the row
                    // opens the AirDrop window.
                    ConnectivityRow {
                        width: parent.width
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

            // A fixed column: nested layouts fill by default, and on some Qt
            // versions that took all the width from the connectivity card.
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: 106
                Layout.maximumWidth: 106
                spacing: 8
                ActionTile {
                    Layout.fillWidth: true
                    icon: "moon"; title: "Focus"; subtitle: cc.notifications?.dnd ? "On" : ""
                    on: cc.notifications?.dnd ?? false
                    onActivated: Quickshell.execDetached(["gg-pref", "focus.dnd", (cc.notifications?.dnd ?? false) ? "false" : "true"])
                }
                ActionTile {
                    Layout.fillWidth: true
                    icon: "mirror"; title: "Screen"; subtitle: cc.airplayOn ? "AirPlay On" : "Mirroring"; on: cc.airplayOn
                    onActivated: cc.showDetail("mirroring")
                }
            }
        }

        BigSurSlider {
            Layout.fillWidth: true
            title: "Display"; lowIcon: "sun"; highIcon: "sun-max"; value: cc.brightness
            onMoved: value => {
                cc.brightness = value
                cc.run("brightnessctl -q set " + Math.round(Math.max(0.02, value) * 100) + "%")
                Quickshell.execDetached(["gg-pref", "display.brightness", String(value)])
            }
        }

        BigSurSlider {
            Layout.fillWidth: true
            title: "Sound"; lowIcon: "speaker"; highIcon: "speaker-wave"
            expandable: true
            onExpand: cc.showDetail("sound")
            value: cc.sink?.audio?.volume ?? 0
            onMoved: value => { if (cc.sink?.audio) cc.sink.audio.volume = value }
        }

        GroupCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            RowLayout {
                anchors { fill: parent; margins: 11 }
                spacing: 11
                Rectangle {
                    Layout.preferredWidth: 58; Layout.preferredHeight: 58
                    radius: 12; clip: true
                    color: "#7c7ce7"
                    Image { anchors.fill: parent; source: cc.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop }
                    Symbol { anchors.centerIn: parent; visible: !(cc.player?.trackArtUrl); name: "music"; size: 24; tone: "white" }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: cc.player?.trackTitle || "Not Playing"
                        color: Theme.label
                        elide: Text.ElideRight
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: cc.player?.trackArtist || "Media"
                        color: Theme.secondaryLabel
                        elide: Text.ElideRight
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                    Item { Layout.preferredHeight: 4 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [
                                ["backward", () => cc.player?.previous()],
                                [cc.player?.isPlaying ? "pause" : "play", () => cc.player?.togglePlaying()],
                                ["forward", () => cc.player?.next()]
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredWidth: 32; Layout.preferredHeight: 28
                                radius: 8
                                color: mediaArea.containsMouse ? (Theme.dark ? "#18ffffff" : "#0e000000") : "transparent"
                                Symbol { anchors.centerIn: parent; name: modelData[0]; size: 17; tone: "auto" }
                                MouseArea { id: mediaArea; anchors.fill: parent; hoverEnabled: true; onClicked: modelData[1]() }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionTile {
                Layout.fillWidth: true; Layout.preferredHeight: 78
                icon: "sun"; title: "Night Shift"; subtitle: cc.nightShift ? "On" : ""; on: cc.nightShift
                onActivated: {
                    const enabled = !cc.nightShift
                    Quickshell.execDetached(["gg-pref", "display.nightShift", enabled ? "true" : "false"])
                    cc.run(enabled ? "hyprsunset -t " + Prefs.displayWarmth : "pkill -x hyprsunset")
                }
            }
            ActionTile {
                Layout.fillWidth: true; Layout.preferredHeight: 78
                icon: "contrast"; title: "Appearance"; subtitle: Theme.dark ? "Dark" : "Light"; on: Theme.dark
                onActivated: {
                    Theme.dark = !Theme.dark
                    cc.run("gsettings set org.gnome.desktop.interface color-scheme " + (Theme.dark ? "prefer-dark" : "default"))
                    Quickshell.execDetached(["sh", "-c",
                        "d=$HOME/.config/golden-gate; mkdir -p \"$d\"; printf '{ \"mode\": \"%s\" }\\n' \"$1\" > \"$d/appearance.json\"",
                        "sh", Theme.dark ? "dark" : "light"])
                }
            }
            ActionTile {
                Layout.fillWidth: true; Layout.preferredHeight: 78
                icon: "screenshot"; title: "Capture"; subtitle: ""
                onActivated: {
                    cc.open = false
                    cc.run("qs -c golden-gate ipc call screenshot toolbar")
                }
            }
        }
    }

    // The detail view's card, the same fill as the grid's modules; it follows
    // the view as it slides and fades.
    Rectangle {
        x: detailView.x - 4; y: detailView.y - 4
        width: detailView.width + 8; height: detailView.height + 8
        radius: 17
        color: Theme.dark ? "#1affffff" : "#8cffffff"
        border { width: 0.5; color: Theme.dark ? "#1affffff" : "#0f000000" }
        opacity: detailView.opacity
        visible: detailView.visible
        transform: Translate { x: detailShift.x }
    }

    // The detail view of one module, in the same panel.
    ColumnLayout {
        id: detailView
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 12; leftMargin: 12; rightMargin: 12 }
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
