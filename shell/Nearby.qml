// Nearby devices: when headphones or an iPhone come close, a card rises from
// the bottom of the screen, as on an iPhone when you open your AirPods case.
//   Headphones   their name and picture, and Connect: pair, trust and
//                connect in one step, then Connected and the card goes.
//   iPhone       once, while Messages isn't set up: Set Up Messages.
// nearby/nearby.py finds them (short, close-range Bluetooth scans). A card the
// user closes stays away for that device for ten minutes; scanning pauses
// while Bluetooth audio plays, so it can't disturb the sound.
//   qs ipc call nearby offer headphones "AirPods Pro"    (for tests)
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import QtQuick
import "ui" as Shared
import "ui/theme"
import "components"

PanelWindow {
    id: nearby
    property var device: null            // the card's device, or null
    property string phase: ""            // "" | "connecting" | "connected" | "failed"
    property var snoozed: ({})           // mac (or "phone") → time it may show again
    property bool messagesReady: true    // BlueFerry has a phone already (or isn't installed)
    readonly property bool shown: !!device
    readonly property bool audioConnected: (Bluetooth.devices?.values ?? []).some((d) => d.connected && String(d.icon).startsWith("audio"))
    readonly property bool adapterOn: Bluetooth.defaultAdapter?.enabled ?? false

    function offer(d) {
        if (!d || device) return
        const key = d.kind === "phone" ? "phone" : d.mac
        if ((snoozed[key] || 0) > Date.now()) return
        if (d.kind === "headphones" && d.connected) return
        if (d.kind === "phone" && messagesReady) return
        device = d
        phase = ""
        autoHide.restart()
    }
    function close() {
        if (device) {
            const s = Object.assign({}, snoozed)
            s[device.kind === "phone" ? "phone" : device.mac] = Date.now() + (device.kind === "phone" ? 30 : 10) * 60000
            snoozed = s
        }
        device = null
        phase = ""
    }
    function act() {
        if (!device) return
        if (device.kind === "phone") {
            DesktopEntries.byId("org.goldengate.Messages")?.execute()
            close()
            return
        }
        phase = "connecting"
        autoHide.stop()
        connectProc.command = ["sh", "-c",
            'bluetoothctl --agent NoInputNoOutput --timeout 30 pair "$1" >/dev/null 2>&1; ' +
            'bluetoothctl trust "$1" >/dev/null 2>&1; ' +
            'bluetoothctl --timeout 20 connect "$1" 2>&1 | grep -q "Connection successful"', "sh", device.mac]
        connectProc.running = true
    }

    Process {
        id: scanner
        running: nearby.adapterOn
        command: ["python3", Quickshell.shellDir + "/nearby/nearby.py"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => { try { nearby.offer(JSON.parse(line)) } catch (e) {} }
        }
        // If the scanner stops while Bluetooth is on, start it again: soon at
        // first, then less often if it keeps stopping.
        onExited: if (nearby.adapterOn) { rescan.interval = Math.min(rescan.interval * 2, 60000); rescan.start() }
        onRunningChanged: if (running) steady.restart()
    }
    Timer { id: rescan; interval: 2500; onTriggered: if (nearby.adapterOn) scanner.running = true }
    Timer { id: steady; interval: 120000; onTriggered: rescan.interval = 2500 }   // running fine: forget the back-off
    // Quiet while Bluetooth audio plays, or while a card is up.
    readonly property bool quiet: audioConnected || shown
    onQuietChanged: if (scanner.running) scanner.write(quiet ? "pause\n" : "resume\n")
    Process {
        id: messagesProbe
        running: true
        command: ["sh", "-c", "command -v blueferry >/dev/null || exit 2; blueferry pairing-configuration-json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { nearby.messagesReady = JSON.parse(text.trim().split("\n").pop()).configured === true }
                catch (e) { nearby.messagesReady = true }
            }
        }
        onExited: (code) => { if (code !== 0) nearby.messagesReady = true }
    }
    Process {
        id: connectProc
        onExited: (code) => {
            nearby.phase = code === 0 ? "connected" : "failed"
            if (code === 0) doneTimer.restart()
        }
    }
    Timer { id: doneTimer; interval: 2200; onTriggered: { nearby.device = null; nearby.phase = "" } }
    // An unanswered card slips away after a while, like the iPhone's.
    Timer { id: autoHide; interval: 25000; onTriggered: if (nearby.phase === "") nearby.close() }

    IpcHandler {
        target: "nearby"
        function offer(kind: string, name: string): void {
            nearby.messagesReady = false
            nearby.offer({ mac: "00:00:00:00:00:00", kind: kind, name: name, model: name, paired: false, connected: false })
        }
        function dismiss(): void { nearby.close() }
    }

    screen: Quickshell.screens.find((s) => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 380
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: shown || card.y < height
    WlrLayershell.namespace: "gg-nearby"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region { item: card }

    // ------------------------------------------------------------- the card
    Shared.Glass {
        id: card
        role: "regular"
        width: 360
        height: 236
        radius: 38
        x: (parent.width - width) / 2
        // Rises from below the screen edge; drops back when dismissed.
        y: nearby.shown ? parent.height - height - 104 : parent.height + 20      // above the Dock
        Behavior on y {
            enabled: !Theme.reduceMotion
            SpringAnimation { spring: 3.2; damping: 0.28; epsilon: 0.25 }
        }
        opacity: nearby.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 220 } }

        // Close.
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 14 }
            width: 26; height: 26; radius: 13
            color: closeArea.containsMouse ? Theme.fill : Theme.dark ? "#26ffffff" : "#14000000"
            Shared.Symbol { anchors.centerIn: parent; name: "xmark"; size: 10; tone: "auto" }
            MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: nearby.close() }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 20; leftMargin: 24; rightMargin: 24 }
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !nearby.device ? "" : nearby.device.kind === "phone" ? "iPhone" : (nearby.device.model || nearby.device.name)
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: Theme.fs(20); weight: Font.Bold }
            }

            // The device: its glyph in a soft disc that floats a little.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                Rectangle {
                    id: halo
                    anchors.centerIn: parent
                    width: 96; height: 96; radius: 48
                    color: "transparent"
                    border { width: 2; color: Theme.accent }
                    opacity: 0
                    SequentialAnimation on scale {
                        running: nearby.shown && nearby.phase === "connecting" && !Theme.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 1.25; duration: 1100; easing.type: Easing.OutCubic }
                    }
                    SequentialAnimation on opacity {
                        running: nearby.shown && nearby.phase === "connecting" && !Theme.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.6; to: 0; duration: 1100; easing.type: Easing.OutCubic }
                    }
                }
                Rectangle {
                    id: disc
                    anchors.centerIn: parent
                    width: 84; height: 84; radius: 42
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.dark ? "#4a4a50" : "#ffffff" }
                        GradientStop { position: 1; color: Theme.dark ? "#2c2c30" : "#e4e6eb" }
                    }
                    border { width: 0.5; color: Theme.separator }
                    Shared.Symbol {
                        anchors.centerIn: parent
                        name: nearby.phase === "connected" ? "checkmark" : nearby.device && nearby.device.kind === "phone" ? "smartphone" : "headphones"
                        size: 40
                        tone: nearby.phase === "connected" ? "accent" : "auto"
                    }
                    SequentialAnimation on anchors.verticalCenterOffset {
                        running: nearby.shown && nearby.phase === "" && !Theme.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: -4; duration: 1400; easing.type: Easing.InOutSine }
                        NumberAnimation { from: -4; to: 0; duration: 1400; easing.type: Easing.InOutSine }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: !nearby.device ? ""
                    : nearby.phase === "connecting" ? "Connecting…"
                    : nearby.phase === "connected" ? "Connected"
                    : nearby.phase === "failed" ? "Couldn't connect. Put them in pairing mode and try again."
                    : nearby.device.kind === "phone" ? "Send and receive your messages on this computer."
                    : nearby.device.paired ? nearby.device.name : "Not Connected"
                color: nearby.phase === "failed" ? "#ff453a" : Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
        }

        Shared.Button {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
            height: 38
            prominent: true
            enabled: nearby.phase !== "connecting" && nearby.phase !== "connected"
            text: !nearby.device ? "" : nearby.device.kind === "phone" ? "Set Up Messages"
                : nearby.phase === "failed" ? "Try Again" : "Connect"
            onClicked: nearby.act()
        }
    }
}
