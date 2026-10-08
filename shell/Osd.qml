// The volume and brightness indicator: a small glass panel under the right end
// of the menu bar, as in macOS 26 and 27, shown when the keys change a level
// and gone 1.5 s after the last press.
//   qs ipc call osd volume      (or brightness)
// Hyprland's media-key bindings change the level themselves and then call this,
// so the keys keep working even while the shell restarts.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"

PanelWindow {
    id: osd
    property string kind: ""            // "volume" | "brightness"
    property bool shown: false
    property real brightness: 0
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: kind === "volume" && (sink?.audio?.muted ?? false)
    readonly property real level: kind === "volume" ? (muted ? 0 : (sink?.audio?.volume ?? 0)) : brightness

    function show(what) {
        if (what !== "volume" && what !== "brightness") return
        kind = what
        if (what === "brightness") readBrightness.running = true
        shown = true
        hide.restart()
    }

    PwObjectTracker { objects: [osd.sink] }
    Process {
        id: readBrightness
        command: ["brightnessctl", "-m"]
        stdout: SplitParser {
            onRead: (line) => {
                const bits = line.split(",")
                if (bits.length > 3) osd.brightness = parseInt(bits[3]) / 100
            }
        }
    }
    Timer { id: hide; interval: 1500; onTriggered: osd.shown = false }
    IpcHandler {
        target: "osd"
        function volume(): void { osd.show("volume") }
        function brightness(): void { osd.show("brightness") }
    }

    screen: Quickshell.screens.find((s) => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 22; right: 6 }       // the panel sits just under the menu bar
    implicitWidth: 300
    implicitHeight: 84
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: shown || panel.opacity > 0
    mask: Region {}                     // never takes input
    WlrLayershell.namespace: "gg-osd"
    // What its glass bends: the desktop under it.
    DesktopBackdrop { surface: osd; namespace: "gg-osd" }
    WlrLayershell.layer: WlrLayer.Overlay

    Glass {
        id: panel
        role: "regular"
        anchors { fill: parent; margins: 10 }
        radius: 20
        opacity: osd.shown ? 1 : 0
        scale: osd.shown || Theme.reduceMotion ? 1 : 0.94
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : (osd.shown ? 120 : 260) } }
        Behavior on scale { Spring { spring: Theme.popover } }

        ColumnLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 9; bottomMargin: 11 }
            spacing: 7
            Text {
                text: osd.kind === "volume" ? (osd.muted ? "Sound (Muted)" : "Sound") : "Display"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 9
                Symbol { name: osd.kind === "volume" ? "speaker" : "sun"; size: 13; tone: "auto"; opacity: 0.6 }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.dark ? "#33ffffff" : "#1f000000"
                    Rectangle {
                        height: parent.height
                        radius: 3
                        width: Math.max(height, parent.width * Math.max(0, Math.min(1, osd.level)))
                        color: Theme.dark ? "#ffffff" : "#3c3c43"
                        opacity: osd.level > 0 ? 1 : 0
                        Behavior on width { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
                    }
                }
                Symbol { name: osd.kind === "volume" ? "speaker-wave" : "sun-max"; size: 15; tone: "auto"; opacity: 0.6 }
            }
        }
    }
}
