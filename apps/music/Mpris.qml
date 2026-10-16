// An optional system media publisher. It never owns the playback state.
import QtQuick
import Quickshell.Io

Item {
    id: bridge
    required property var player
    property bool available: false
    property string error: ""
    signal raiseRequested()
    signal quitRequested()
    signal openRequested(string path)
    readonly property string stateText: JSON.stringify(player.systemState())
    onStateTextChanged: publishDelay.restart()
    function publish(seeked = false) {
        if (!available || !worker.running) return
        const state = player.systemState()
        if (seeked) state.seeked = true
        worker.write(JSON.stringify(state) + "\n")
    }
    function retry() { if (!worker.running) { error = ""; worker.running = true } }
    function command(event) {
        switch (event.command) {
        case "play": player.play(); break
        case "pause": player.pause(); break
        case "stop": player.stop(); break
        case "toggle": player.toggle(); break
        case "next": player.next(); break
        case "previous": player.previous(); break
        case "seek": player.seek(event.position); break
        case "repeat": player.repeat = event.value; break
        case "shuffle": player.shuffle = event.value; break
        case "volume": player.muted = false; player.volume = event.value; break
        case "raise": raiseRequested(); break
        case "quit": quitRequested(); break
        case "open": openRequested(event.path); break
        }
    }
    Timer { id: publishDelay; interval: 25; onTriggered: bridge.publish() }
    Connections { target: bridge.player; function onSeeked() { bridge.publish(true) } }
    Process {
        id: worker
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("mpris.py").toString().replace("file://", ""))]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const event = JSON.parse(line)
                    if (event.event === "ready") { bridge.available = true; bridge.error = ""; bridge.publish() }
                    else if (event.event === "error") bridge.error = event.error
                    else if (event.command) bridge.command(event)
                } catch (_) {}
            }
        }
        onExited: {
            bridge.available = false
            if (!bridge.error) bridge.error = "System media controls aren't available. Local playback still works."
        }
    }
}
