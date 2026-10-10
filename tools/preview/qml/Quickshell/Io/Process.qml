import QtQuick
// Runs nothing: answers from the preview's fixtures (preview.py), so a
// surface shows what it would with a typical system behind it.
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
    function write(data) {}
    function signal(sig) {}
    function startDetached() { __preview.log("detached " + JSON.stringify(command)) }
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
    onRunningChanged: if (running) __timer.restart()
    Component.onCompleted: if (running) __timer.restart()
}
