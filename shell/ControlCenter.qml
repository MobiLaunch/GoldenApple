// Control Center: free-floating glass modules that spring out of the menu bar.
// Each module is wired to the real service behind it.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import "theme"
import "components"

PanelWindow {
    id: cc
    property bool open: false
    property var notifications
    function toggle() { open = !open; if (open) refresh() }

    visible: open || closeTimer.running
    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    implicitWidth: 64 * 4 + 12 * 3
    implicitHeight: grid.implicitHeight + 40
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-controlcenter"
    WlrLayershell.layer: WlrLayer.Overlay

    onOpenChanged: if (!open) closeTimer.restart()
    Timer { id: closeTimer; interval: 220 }
    HyprlandFocusGrab { windows: [cc]; active: cc.open; onCleared: cc.open = false }

    // ---------------------------------------------------------------- services
    property bool wifiOn: true
    property string ssid: ""
    property real brightness: 0.6
    property bool nightShift: false
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var player: Mpris.players.values.length ? Mpris.players.values[0] : null
    PwObjectTracker { objects: [cc.sink] }

    function run(cmd) { Hyprland.dispatch("exec " + cmd) }
    // Opens an app by its desktop entry, or runs a fallback command without one.
    function openApp(id, fallback) {
        const e = DesktopEntries.byId(id)
        if (e) e.execute(); else run(fallback)
    }
    function refresh() { wifiState.running = true; ssidProc.running = true; brightProc.running = true }

    Process {
        id: wifiState
        command: ["nmcli", "-t", "radio", "wifi"]
        stdout: SplitParser { onRead: (line) => cc.wifiOn = line.trim() === "enabled" }
    }
    Process {
        id: ssidProc
        command: ["sh", "-c", "nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1==\"yes\"{print $2; exit}'"]
        stdout: SplitParser { onRead: (line) => cc.ssid = line }
    }
    Process {
        id: brightProc
        command: ["brightnessctl", "-m"]
        stdout: SplitParser { onRead: (line) => cc.brightness = parseInt(line.split(",")[3]) / 100 }
    }

    // ---------------------------------------------------------------- building blocks
    // Stagger: each module springs in slightly after the previous one.
    component Module: Glass {
        id: mod
        property int order: 0
        // Stagger: each module springs in slightly after the previous one; a timer
        // flips `shown` so the Behaviors below stay simple.
        property bool shown: false
        Timer { interval: 1 + mod.order * 14; running: cc.open && !mod.shown; onTriggered: mod.shown = true }
        Connections { target: cc; function onOpenChanged() { if (!cc.open) mod.shown = false } }
        // Faint cool tint so white glyphs stay legible over bright windows.
        tint: "#3d1c3060"
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.72
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: mod.shown ? 260 : 160 } }
        Behavior on scale { Spring { spring: Theme.popover } }
    }
    component Circle: Module {
        id: c
        property string icon
        property bool on: false
        signal activated()
        Layout.preferredWidth: 64; Layout.preferredHeight: 64
        radius: 32
        filled: on
        pressed: cma.pressed
        hovered: cma.containsMouse
        Symbol { anchors.centerIn: parent; name: c.icon; size: 25; tone: c.on ? "accent" : "white" }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: c.activated() }
    }
    component Wide: Module {
        id: w
        property string icon
        property string title
        property string subtitle
        property bool on: false
        signal activated()
        Layout.columnSpan: 2; Layout.preferredWidth: 140; Layout.preferredHeight: 64
        radius: 32
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
            spacing: 10
            // The toggle is a glass button of its own inside the module.
            Glass {
                implicitWidth: 48; implicitHeight: 48; radius: 24
                tint: Qt.rgba(1, 1, 1, 0.18)
                filled: w.on
                pressed: wma.pressed
                hovered: wma.containsMouse
                Symbol { anchors.centerIn: parent; name: w.icon; size: 22; tone: w.on ? "accent" : "white" }
                MouseArea { id: wma; anchors.fill: parent; hoverEnabled: true; onClicked: w.activated() }
            }
            ColumnLayout {
                spacing: 0
                Text { text: w.title; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                Text { visible: w.subtitle !== ""; text: w.subtitle; color: Qt.rgba(1, 1, 1, 0.72); elide: Text.ElideRight; Layout.maximumWidth: 76; font { family: Theme.fontUi; pixelSize: 12 } }
            }
        }
    }

    // ---------------------------------------------------------------- layout
    GridLayout {
        id: grid
        anchors { top: parent.top; right: parent.right; topMargin: 30 }
        columns: 4
        columnSpacing: 12
        rowSpacing: 12

        Wide {
            order: 0; icon: "wifi"; title: "Wi-Fi"; subtitle: cc.wifiOn ? (cc.ssid || "Not Connected") : "Off"; on: cc.wifiOn
            onActivated: { cc.wifiOn = !cc.wifiOn; cc.run("nmcli radio wifi " + (cc.wifiOn ? "on" : "off")) }
        }
        Module {
            order: 1
            Layout.columnSpan: 2; Layout.rowSpan: 2; Layout.preferredWidth: 140; Layout.preferredHeight: 140
            radius: 32
            ColumnLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 2
                Rectangle {
                    implicitWidth: 44; implicitHeight: 44; radius: 10; clip: true
                    gradient: Gradient { GradientStop { position: 0; color: "#ff5f6d" } GradientStop { position: 1; color: "#ffc371" } }
                    Image { anchors.fill: parent; source: cc.player?.trackArtUrl ?? ""; fillMode: Image.PreserveAspectCrop }
                }
                Item { Layout.fillHeight: true }
                Text { Layout.fillWidth: true; text: cc.player?.trackTitle || "Not Playing"; color: "#ffffff"; elide: Text.ElideRight; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
                Text { Layout.fillWidth: true; text: cc.player?.trackArtist ?? ""; color: Qt.rgba(1, 1, 1, 0.72); elide: Text.ElideRight; font { family: Theme.fontUi; pixelSize: 12 } }
                RowLayout {
                    Layout.fillWidth: true
                    Repeater {
                        model: [["backward", () => cc.player?.previous()], [cc.player?.isPlaying ? "pause" : "play", () => cc.player?.togglePlaying()], ["forward", () => cc.player?.next()]]
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 32
                            Symbol { anchors.centerIn: parent; name: modelData[0]; size: 22 }
                            MouseArea { anchors.fill: parent; onClicked: modelData[1]() }
                        }
                    }
                }
            }
        }
        Circle {
            order: 2; icon: "bluetooth"; on: Bluetooth.defaultAdapter?.enabled ?? false
            onActivated: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
        }
        Circle {
            order: 3; icon: "broadcast"; on: false
            onActivated: cc.run("localsend_app")   // nearby sharing via LocalSend
        }
        Wide {
            order: 4; icon: "moon"; title: "Focus"; on: cc.notifications?.dnd ?? false
            onActivated: if (cc.notifications) cc.notifications.dnd = !cc.notifications.dnd
        }
        Circle {
            order: 5; icon: "sun"; on: cc.nightShift
            onActivated: { cc.nightShift = !cc.nightShift; cc.run(cc.nightShift ? "hyprsunset -t 4500" : "pkill hyprsunset") }
        }
        Circle {
            order: 6; icon: "mirror"
            onActivated: cc.run("wdisplays")
        }
        GlassSlider {
            Layout.columnSpan: 4; Layout.fillWidth: true; Layout.preferredHeight: 64
            title: "Display"; lowIcon: "sun"; highIcon: "sun-max"; value: cc.brightness
            onMoved: (v) => { cc.brightness = v; cc.run("brightnessctl -q set " + Math.round(v * 100) + "%") }
        }
        GlassSlider {
            Layout.columnSpan: 4; Layout.fillWidth: true; Layout.preferredHeight: 64
            title: "Sound"; lowIcon: "speaker"; highIcon: "speaker-wave"; value: cc.sink?.audio?.volume ?? 0
            onMoved: (v) => { if (cc.sink?.audio) cc.sink.audio.volume = v }
        }
        Circle {
            order: 9; icon: "contrast"; on: Theme.dark
            onActivated: {
                Theme.dark = !Theme.dark
                cc.run("gsettings set org.gnome.desktop.interface color-scheme " + (Theme.dark ? "prefer-dark" : "default"))
                // A choice made here ends Auto (Setup Assistant's day/night switching).
                Quickshell.execDetached(["sh", "-c", "d=\"${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate\"; mkdir -p \"$d\" && printf '{ \"mode\": \"%s\" }\\n' \"$1\" > \"$d/appearance.json\"",
                                         "sh", Theme.dark ? "dark" : "light"])
            }
        }
        Circle { order: 10; icon: "calculator"; onActivated: { cc.open = false; cc.openApp("org.goldengate.Calculator", "gnome-calculator") } }
        Circle { order: 11; icon: "timer"; onActivated: { cc.open = false; cc.run("gnome-clocks") } }
        Circle { order: 12; icon: "screenshot"; onActivated: { cc.open = false; cc.run("sh -c 'sleep 0.3; grim -g \"$(slurp)\" ~/Pictures/Screenshot-$(date +%F-%H%M%S).png'") } }
    }
}
