// The AirDrop service (airdropd.py), through its client relay: JSON lines in
// both directions. The relay starts the service if it isn't running yet.
//   service.send({ cmd: "scan" })
// Events arrive through event(name, data). GG_AIRDROP_CLIENT overrides the
// relay command (tests use a stand-in).
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: service
    signal event(string name, var data)
    property bool started: false
    property var queue: []
    readonly property string helper: Qt.resolvedUrl("airdropd.py").toString().replace("file://", "")

    function send(msg) {
        const line = JSON.stringify(msg) + "\n"
        if (started) proc.write(line)
        else queue.push(line)
    }

    Process {
        id: proc
        running: true
        command: Quickshell.env("GG_AIRDROP_CLIENT") ? ["sh", "-c", Quickshell.env("GG_AIRDROP_CLIENT")]
                                                     : ["python3", service.helper, "client"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => {
                let msg
                try { msg = JSON.parse(line) } catch (e) { return }
                if (typeof msg.event === "string") service.event(msg.event, msg)
            }
        }
        onStarted: {
            service.started = true
            const lines = service.queue
            service.queue = []
            for (const l of lines) proc.write(l)
        }
        onExited: {
            service.started = false
            restart.start()
        }
    }
    // The service went away (or never started): try again, and say hello so
    // the window gets the current state.
    Timer {
        id: restart
        interval: 2000
        onTriggered: { service.queue = [JSON.stringify({ cmd: "hello" }) + "\n"]; proc.running = true }
    }
}
