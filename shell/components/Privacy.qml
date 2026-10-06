pragma Singleton
// Who is using the microphone, camera, screen and location, from
// ui/privacy/monitor.py (PipeWire's graph, /proc, GeoClue). The menu bar
// shows a dot for each (location as an arrow); Control Center names the apps.
// GG_PRIVACY_PREVIEW='{"mic":["Citron"]}' stands in for the monitor (tests).
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: privacy
    property var mic: []
    property var camera: []
    property var screen: []
    property var location: []
    readonly property bool any: mic.length + camera.length + screen.length + location.length > 0
    // As on the Mac, with location in blue and the microphone in yellow.
    readonly property var colors: ({ mic: "#ffb800", camera: "#30d158", screen: "#bf5af2", location: "#0a84ff" })
    readonly property var names: ({ mic: "Microphone", camera: "Camera", screen: "Screen", location: "Location" })
    readonly property string preview: Quickshell.env("GG_PRIVACY_PREVIEW") || ""
    readonly property string helper: decodeURIComponent(
        Qt.resolvedUrl("../ui/privacy/monitor.py").toString().replace("file://", ""))

    function take(line) {
        try {
            const s = JSON.parse(line)
            mic = s.mic ?? []; camera = s.camera ?? []; screen = s.screen ?? []; location = s.location ?? []
        } catch (e) {}
    }
    Component.onCompleted: if (preview) take(preview)

    Process {
        id: monitor
        running: !privacy.preview
        command: ["python3", privacy.helper]
        stdout: SplitParser { onRead: (line) => privacy.take(line) }
        // Never leave a stale dot: clear, then follow again shortly.
        onExited: { privacy.take("{}"); again.start() }
    }
    Timer { id: again; interval: 5000; onTriggered: monitor.running = true }
}
