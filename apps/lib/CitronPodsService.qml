// First-party interface to the CitronPods M10 daemon. There is no second
// application/window/BlueZ owner: the daemon owns device state and this
// lightweight Quickshell component reads its private atomic snapshot.
// D-Bus is used only for commands and compatibility recovery.
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: pods
    visible: false
    width: 0; height: 0

    property bool enabled: true
    property bool online: false
    property bool initialized: false
    property string error: ""
    property var state: ({})
    property var devices: state.devices ?? []
    property var nearby: state.nearbyAirPods ?? []
    property var activeDevice: state.activeDevice ?? ({})
    readonly property bool connected: activeDevice.connected === true
    readonly property bool canControl: online && connected && state.protocolAvailable === true
    readonly property string status: !online ? "CitronPods service unavailable"
        : connected ? "Connected" : activeDevice.paired ? "Not connected" : "No AirPods connected"
    readonly property string service: "org.citronos.CitronPods1"
    readonly property string objectPath: "/org/citronos/CitronPods"
    property string instanceId: ""
    property double lastSequence: -1
    property double lastUpdate: 0
    property bool snapshotValid: false
    property bool pending: false
    signal connectedTransition(var device)
    signal popupRequested(string address)

    function acceptState(next, snapshot) {
        if (!next || next.apiVersion !== 1) throw new Error("Incompatible CitronPods protocol")
        if (snapshot && (typeof next.updatedAtMs !== "number"
                         || Math.abs(Date.now() - next.updatedAtMs) > 22000))
            throw new Error("Expired CitronPods status")
        const instance = String(next.daemonInstance ?? "")
        const wasSame = instance === instanceId
        const before = wasSame && connected
        const seen = initialized && wasSame
        const oldSeq = wasSame ? lastSequence : -1
        instanceId = instance
        state = next
        online = true
        initialized = true
        error = ""
        lastUpdate = Date.now()
        if (snapshot) snapshotValid = true
        const seq = Number(next.popupSequence ?? 0)
        if (Number.isFinite(seq) && seq >= 0) {
            lastSequence = seq
            if (seen && oldSeq >= 0 && seq > oldSeq && next.popupAddress)
                popupRequested(String(next.popupAddress))
        }
        // An unauthenticated BLE advertisement must never trigger a popup.
        if (seen && !before && connected && activeDevice.trusted === true)
            connectedTransition(activeDevice)
    }

    FileView {
        id: snapshot
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/nonexistent") + "/citronpods/state.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { pods.acceptState(JSON.parse(text()), true) }
            catch (e) { pods.snapshotValid = false; pods.error = String(e) }
        }
        onLoadFailed: pods.snapshotValid = false
    }
    Process {
        id: recovery
        command: ["busctl", "--user", "--json=short", "call", pods.service,
                  pods.objectPath, pods.service, "GetState"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim()).data[0]
                    pods.acceptState(JSON.parse(data), false)
                } catch (e) { pods.error = String(e) }
            }
        }
        onExited: (code) => {
            pods.pending = false
            if (code !== 0 && !pods.snapshotValid) {
                pods.online = false
                pods.initialized = false
                pods.error = "CitronPods daemon is not responding"
            }
        }
    }
    Timer {
        interval: 5000
        running: pods.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (pods.snapshotValid && Date.now() - pods.lastUpdate > 22000) {
                pods.snapshotValid = false
                pods.online = false
                pods.error = "CitronPods status is stale"
            }
            if (!pods.snapshotValid) pods.refresh()
        }
    }
    function refresh() {
        if (!enabled || snapshotValid || pending || recovery.running) return
        pending = true
        recovery.running = true
    }
    function command(method, signature, args) {
        if (!online) return
        const cmd = ["busctl", "--user", "call", service, objectPath, service, method]
        if (signature) cmd.push(signature)
        for (const arg of (args ?? [])) cmd.push(String(arg))
        Quickshell.execDetached(cmd)
    }
    function select(address) { if (address) command("SetActiveAddress", "s", [address]) }
    function connectDevice(address) { if (address) command("ConnectDevice", "s", [address]) }
    function disconnectDevice(address) { if (address) command("DisconnectDevice", "s", [address]) }
    function startDiscovery() { command("StartDiscovery", "", []) }
    function stopDiscovery() { command("StopDiscovery", "", []) }
    function scanTelemetry() { command("ScanTelemetry", "", []) }
    function setNoiseMode(mode) {
        if (canControl && Number.isInteger(mode) && mode >= 0 && mode <= 3)
            command("SetNoiseMode", "i", [mode])
    }
    function setConversationAwareness(on) {
        if (canControl) command("SetConversationAwareness", "b", [on ? "true" : "false"])
    }
    function setRouteAudio(on) { command("SetRouteAudio", "b", [on ? "true" : "false"]) }
    function setEarDetection(on) { command("SetAutomaticEarDetection", "b", [on ? "true" : "false"]) }
    function setAutoPopup(on) { command("SetAutoPopupEnabled", "b", [on ? "true" : "false"]) }
}
