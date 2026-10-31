import QtQuick
// Runs nothing: answers from the preview's fixtures (preview.py), so a
// surface shows what it would with a typical system behind it.
// A test can let one kind of long-lived program run for real: with a
// `__spawner` in the context (tests/settingsd.py), dbus-bridge.py is started
// and talked to as Quickshell would.
QtObject {
    id: proc
    property var command: []
    property bool running: false
    property var environment: ({})
    property bool clearEnvironment: false
    property string workingDirectory
    property bool stdinEnabled: false
    property QtObject stdout
    property QtObject stderr
    property int processId: 0
    signal started()
    signal exited(int exitCode, int exitStatus)
    // What a program would be sent on stdin, for tests (secrets go here, not argv).
    function write(data) {
        if (__live) __live.write(String(data))
        else __preview.log("stdin " + JSON.stringify({ command: proc.command, data: String(data) }))
    }
    function signal(sig) {}
    function startDetached() { __preview.log("detached " + JSON.stringify(command)) }
    property QtObject __live: null
    function __spawns() {
        return typeof __spawner !== "undefined" && (proc.command ?? []).some((c) => String(c).endsWith("/dbus-bridge.py"))
    }
    function __start() {
        if (__live) return
        if (!__spawns()) { __timer.restart(); return }
        __live = __spawner.spawn(proc.command)
        __live.line.connect((l) => { if (proc.stdout && proc.stdout.__feed) proc.stdout.__feed(l + "\n") })
        __live.finished.connect((code) => { proc.__live = null; proc.running = false; proc.exited(code, 0) })
        proc.started()
    }
    property QtObject __timer: Timer {
        interval: 1
        onTriggered: {
            const r = __preview.run(proc.command)
            proc.started()
            if (r.hang) return                  // a monitor: runs until stopped
            for (const p of [proc.stdout, proc.stderr]) {
                if (!p) continue
                const text = p === proc.stdout ? r.stdout : r.stderr
                if (p.__feed) p.__feed(text)
            }
            proc.running = false
            proc.exited(r.code, 0)
        }
    }
    onRunningChanged: if (running) __start()
    Component.onCompleted: if (running) __start()
    Component.onDestruction: if (__live) __live.kill()
}
