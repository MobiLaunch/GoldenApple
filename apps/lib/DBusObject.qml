// One D-Bus object, reached through dbus-bridge.py (Quickshell has no general
// D-Bus type yet). The bridge runs while the item lives; `ready` says the
// object answered (its service is started if need be).
//   DBusObject {
//       id: settingsd
//       service: "org.citronos.Settings1"; path: "/org/citronos/Settings1"
//       signalNames: ["Changed"]
//       onSignalled: (name, args) => …
//   }
//   settingsd.call("Get", ["desktop", "dock.size"], (ok, result, error) => …)
// A call made while it isn't ready, or cut off because the bridge stopped,
// fails at once with error "unavailable", so a caller can do it another way.
// `unreachable` is set once the bridge itself has stopped without reaching
// the object (no bus, no service), not while a service is merely restarting:
// the moment for a caller to stand in for it.
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: object
    property string bus: "session"
    property string service
    property string path
    property string iface: service
    property var signalNames: []
    property bool active: true
    readonly property bool ready: live
    property bool live: false
    property string error: ""             // why it isn't ready, when it said
    property bool unreachable: false
    signal signalled(string name, var args)

    property int nextId: 1
    property var waiting: ({})            // id → done(ok, result, error)
    readonly property string bridge: decodeURIComponent(Qt.resolvedUrl("dbus-bridge.py").toString().replace("file://", ""))

    function call(method, args, done) {
        if (!live) {
            if (done) done(false, null, "unavailable")
            return false
        }
        const id = nextId++
        if (done) waiting[id] = done
        bridgeProcess.write(JSON.stringify({ id: id, call: method, args: args ?? [] }) + "\n")
        return true
    }
    function take(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.signal !== undefined) { signalled(msg.signal, msg.args ?? []); return }
        if (msg.ready !== undefined) {
            if (!msg.ready) fail("unavailable")
            error = msg.error ?? ""
            live = msg.ready
            if (live) unreachable = false
            return
        }
        const done = waiting[msg.id]
        if (!done) return
        delete waiting[msg.id]
        done(msg.ok === true, msg.result ?? null, msg.ok ? "" : (msg.message || msg.error || "it failed"))
    }
    function fail(why) {
        const all = waiting
        waiting = ({})
        for (const id in all) all[id](false, null, why)
    }

    Process {
        id: bridgeProcess
        command: ["python3", object.bridge, "--bus", object.bus, "--dest", object.service, "--path", object.path,
                  "--interface", object.iface].concat(object.signalNames.reduce((a, s) => a.concat(["--signal", s]), []))
        running: object.active && object.service !== "" && object.path !== ""
        stdinEnabled: true
        stdout: SplitParser { onRead: (line) => object.take(line) }
        onExited: {
            object.live = false
            object.unreachable = true
            object.fail("unavailable")
            if (object.active) retry.restart()
        }
    }
    // A bridge that couldn't reach its object (no bus yet, no service) tries
    // again now and then; meanwhile callers do without it.
    Timer {
        id: retry
        interval: 30000
        onTriggered: if (object.active && !bridgeProcess.running) bridgeProcess.running = true
    }
}
