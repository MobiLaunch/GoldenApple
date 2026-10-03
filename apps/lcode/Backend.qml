// The LCode helper (helper.py serve): one long-running process, JSON lines
// both ways. call() sends a request and hands the reply to its callback;
// unsolicited events arrive through event().
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: backend
    signal event(var e)
    property int nextId: 1
    property var pending: ({})
    readonly property bool ready: proc.running
    readonly property string helper: Qt.resolvedUrl("helper.py").toString().replace("file://", "")

    function call(cmd, args, callback) {
        const id = nextId++
        if (callback)
            pending[id] = callback
        proc.write(JSON.stringify(Object.assign({ id: id, cmd: cmd }, args || {})) + "\n")
    }

    function receive(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.id !== undefined) {
            const cb = pending[msg.id]
            delete pending[msg.id]
            if (cb)
                cb(msg)
        } else if (msg.event) {
            backend.event(msg)
        }
    }

    Process {
        id: proc
        running: true
        stdinEnabled: true
        command: ["python3", backend.helper, "serve"]
        stdout: SplitParser { onRead: (line) => backend.receive(line) }
        // The helper only stops with LCode; restart it if it ever dies.
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 800
        onTriggered: proc.running = true
    }
}
