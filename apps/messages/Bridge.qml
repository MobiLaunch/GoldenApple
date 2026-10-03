// BlueFerry's Quickshell bridge: one long-running helper that speaks JSON lines
// and forwards them to BlueFerry's session D-Bus service, which talks to the
// paired iPhone over Bluetooth (MAP for messages, PBAP for contacts).
//   bridge.call("threads", { limit: 200 }, (ok, result) => …)
// Events ("history-changed", "status-changed", "open-message") arrive through
// event(name, data). Requests made before the helper starts wait in a queue:
// a write to a process that isn't running is dropped.
// GG_BLUEFERRY_BRIDGE overrides the helper (tests use a stand-in).
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: bridge
    signal event(string name, var data)
    signal failed(string message)
    readonly property string program: Quickshell.env("GG_BLUEFERRY_BRIDGE") || "/usr/bin/blueferry-quickshell-bridge"
    property bool available: false       // BlueFerry is installed
    property bool checked: false         // the check above has run
    property bool started: false
    property int nextId: 1
    property var pending: ({})
    property var queue: []

    function call(method, args, callback) {
        const id = nextId++
        if (callback) pending[id] = callback
        const line = JSON.stringify({ id: id, method: method, args: args || {} }) + "\n"
        if (started) proc.write(line)
        else {
            queue.push(line)
            if (!proc.running && available && checked) proc.running = true
        }
    }

    function receive(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (typeof msg.event === "string") { bridge.event(msg.event, msg.data); return }
        const cb = pending[msg.id]
        delete pending[msg.id]
        if (cb) cb(msg.ok === true, msg.ok === true ? msg.result : String(msg.error || "BlueFerry request failed"))
        else if (msg.ok !== true && msg.error) bridge.failed(String(msg.error))
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v \"$1\" >/dev/null", "sh", bridge.program]
        onExited: (code) => {
            bridge.available = code === 0
            bridge.checked = true
            if (bridge.available) proc.running = true
            else {
                for (const id in bridge.pending) bridge.pending[id](false, "BlueFerry isn't installed")
                bridge.pending = ({})
                bridge.queue = []
            }
        }
    }
    Process {
        id: proc
        running: false
        command: [bridge.program]
        stdinEnabled: true
        stdout: SplitParser { onRead: (line) => bridge.receive(line) }
        onStarted: {
            bridge.started = true
            const lines = bridge.queue
            bridge.queue = []
            for (const l of lines) proc.write(l)
        }
        onExited: (code) => {
            bridge.started = false
            // Pending callbacks will never be answered by this process.
            for (const id in bridge.pending) bridge.pending[id](false, "BlueFerry stopped")
            bridge.pending = ({})
            restart.start()
        }
    }
    Timer { id: restart; interval: 2000; onTriggered: if (bridge.available) proc.running = true }
}
