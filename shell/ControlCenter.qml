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
import "theme"
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
    function run(cmd) { Hyprland.dispatch("exec " + cmd) }
    function refresh() {
        wifiState.running = true
        ssidProc.running = true
        brightProc.running = true
    }

    visible: open || closeTimer.running
    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    implicitWidth: 356
    implicitHeight: panel.height + 42
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-controlcenter"
    WlrLayershell.layer: WlrLayer.Overlay

    onOpenChanged: if (!open) closeTimer.restart()
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
        radius: 17
        color: Theme.dark ? "#5effffff" : "#72ffffff"
        border { width: 0.5; color: Theme.dark ? "#24ffffff" : "#18000000" }
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
        Symbol { id: chevron; anchors { right: parent.right; verticalCenter: parent.verticalCenter }; name: "chevron-right"; size: 11; tone: "gray" }
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
            width: 34; height: 34; radius: 17
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
        signal moved(real value)
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
        RowLayout {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 13; rightMargin: 13; bottomMargin: 11 }
            spacing: 8
            Symbol { name: slider.lowIcon; size: 13; tone: "gray" }
            Item {
                id: track
                Layout.fillWidth: true
                height: 18
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 7; radius: 3.5
                    color: Theme.dark ? "#38ffffff" : "#1d000000"
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.max(0, Math.min(1, slider.value))
                    height: 7; radius: 3.5
                    color: "#f2ffffff"
                }
                Rectangle {
                    width: drag.pressed ? 18 : 15
                    height: width; radius: width / 2
                    x: Math.max(0, Math.min(parent.width - width, parent.width * slider.value - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#ffffff"
                    border { width: 0.5; color: "#26000000" }
                    Behavior on width { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 80 } }
                }
                MouseArea {
                    id: drag
                    anchors { fill: parent; topMargin: -7; bottomMargin: -7 }
                    hoverEnabled: true
                    onPressed: mouse => slider.setFromX(mouse.x)
                    onPositionChanged: mouse => { if (pressed) slider.setFromX(mouse.x) }
                }
            }
            Symbol { name: slider.highIcon; size: 15; tone: "gray" }
        }
    }

    Glass {
        id: panel
        variant: "regular"
        anchors { top: parent.top; right: parent.right; topMargin: 24 }
        width: 344
        height: content.implicitHeight + 24
        radius: 25
        tint: Theme.dark ? "#e32b2b30" : "#e5e9e9ed"
        rim: Theme.dark ? "#48ffffff" : "#68ffffff"
        rimLow: Theme.dark ? "#18ffffff" : "#26000000"
        shine: Theme.dark ? "#24ffffff" : "#36ffffff"
        lens: 4
        shadow: "#a8000000"
        opacity: cc.open ? 1 : 0
        scale: cc.open || Prefs.reduceMotion ? 1 : 0.965
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    }

    ColumnLayout {
        id: content
        z: 2
        anchors { top: panel.top; left: panel.left; right: panel.right; topMargin: 12; leftMargin: 12; rightMargin: 12 }
        spacing: 9
        opacity: panel.opacity

        RowLayout {
            Layout.fillWidth: true
            spacing: 9

            GroupCard {
                Layout.fillWidth: true
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
                        onActivated: { cc.open = false; cc.run("gg-settings wifi") }
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
                        onActivated: { cc.open = false; cc.run("gg-settings bluetooth") }
                    }
                    Rectangle { width: parent.width - 48; x: 48; height: 0.5; color: Theme.separator }
                    ConnectivityRow {
                        width: parent.width
                        icon: "broadcast"; title: "Nearby Sharing"; subtitle: "LocalSend"
                        on: false
                        onActivated: { cc.open = false; cc.run("localsend_app") }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 106
                spacing: 8
                ActionTile {
                    Layout.fillWidth: true
                    icon: "moon"; title: "Focus"; subtitle: cc.notifications?.dnd ? "On" : ""
                    on: cc.notifications?.dnd ?? false
                    onActivated: Quickshell.execDetached(["gg-pref", "focus.dnd", (cc.notifications?.dnd ?? false) ? "false" : "true"])
                }
                ActionTile {
                    Layout.fillWidth: true
                    icon: "mirror"; title: "Screen"; subtitle: "Mirroring"; on: false
                    onActivated: { cc.open = false; cc.run("wdisplays") }
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
                Layout.fillWidth: true; Layout.preferredHeight: 66
                icon: "sun"; title: "Night Shift"; subtitle: cc.nightShift ? "On" : ""; on: cc.nightShift
                onActivated: {
                    const enabled = !cc.nightShift
                    Quickshell.execDetached(["gg-pref", "display.nightShift", enabled ? "true" : "false"])
                    cc.run(enabled ? "hyprsunset -t " + Prefs.displayWarmth : "pkill -x hyprsunset")
                }
            }
            ActionTile {
                Layout.fillWidth: true; Layout.preferredHeight: 66
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
                Layout.fillWidth: true; Layout.preferredHeight: 66
                icon: "screenshot"; title: "Capture"; subtitle: ""
                onActivated: {
                    cc.open = false
                    cc.run("sh -c 'sleep 0.25; grim -g \"$(slurp)\" ~/Pictures/Screenshot-$(date +%F-%H%M%S).png'")
                }
            }
        }
    }
}
