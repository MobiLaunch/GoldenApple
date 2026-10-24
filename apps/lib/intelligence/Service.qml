// One helper process per operation. No request contents or API keys in argv.
import Quickshell.Io
import QtQuick

Item {
    id: service
    objectName: "intelligenceService"
    property bool busy: false
    property string error: ""
    property string operation: ""
    property string payload: ""
    property var reply: null
    property bool cancelled: false
    property string terminalError: ""
    property int serial: 0
    signal completed(string action, var result)
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("helper.py").toString().replace("file://", ""))

    function send(request) {
        if (busy) return false
        error = ""
        serial++
        operation = request.action || "generate"
        payload = JSON.stringify(request)
        reply = null
        cancelled = false
        terminalError = ""
        busy = true
        proc.stdinEnabled = true
        proc.running = true
        deadline.restart()
        return true
    }
    // User cancellation is silent; a timeout completes with an error.
    function cancel(reason) {
        if (!busy) return
        terminalError = reason || ""
        cancelled = !terminalError
        payload = ""
        proc.running = false
        if (!proc.running) { const run = serial; Qt.callLater(() => finish(run)) }
    }
    function finish(run) {
        if (!busy || run !== serial || proc.running) return
        deadline.stop()
        const result = terminalError ? {ok: false, error: terminalError, code: "timeout"}
            : reply || { ok: false, error: "The assistant could not start. Check that Python 3 is installed." }
        const action = operation
        const wasCancelled = cancelled
        busy = false
        payload = ""
        reply = null
        terminalError = ""
        if (wasCancelled) return
        error = result.ok ? "" : (result.error || "The request failed.")
        completed(action, result)
    }
    Process {
        id: proc
        command: ["python3", service.helper]
        stdinEnabled: true
        onStarted: {
            write(service.payload)
            service.payload = ""
            stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (service.cancelled) return
                try { service.reply = JSON.parse(text) }
                catch (e) { service.reply = { ok: false, error: "The assistant returned an unreadable result." } }
            }
        }
        onExited: { const run = service.serial; Qt.callLater(() => service.finish(run)) }
    }
    // Failed-to-start may not emit exited on every Quickshell release.
    Timer {
        interval: 2000
        running: service.busy && !proc.running
        onTriggered: service.finish(service.serial)
    }
    Timer {
        id: deadline
        interval: 150000
        onTriggered: {
            service.cancel("The request timed out. Try again.")
        }
    }
    Component.onDestruction: proc.running = false
}
