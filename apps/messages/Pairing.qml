// Connecting an iPhone, through BlueFerry's setup commands (one JSON answer
// each; pairing streams events while the phone and the computer confirm a
// code). The flow, as Messages shows it:
//   check → (Bluetooth needs enabling for iPhone?) → scan → pick the iPhone →
//   pair: compare the code shown on both screens → BlueFerry verifies
//   messages (MAP), contacts (PBAP) and notifications (ANCS) → connected.
// GG_BLUEFERRY overrides the CLI (tests use a stand-in).
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: pairing
    readonly property string cli: Quickshell.env("GG_BLUEFERRY") || "/usr/bin/blueferry"

    // The saved phone.
    property bool configured: false
    property string phoneMac: ""
    property string phoneAdapter: ""
    property bool bonded: true
    // The Bluetooth adapter.
    property bool checkedAdapter: false
    property bool hardwareSupported: true
    property bool pairingReady: true
    property bool notificationsSupported: false
    property bool bluezReady: false
    property bool explicitPairing: false
    property string adapter: ""
    property string issue: ""
    // Scanning and pairing.
    property var devices: []
    property int selected: -1
    property string status: ""
    property string passkey: ""
    property bool confirming: false
    property var transports: ({ map: false, pbap: false, ancs: false })
    property var jobs: ({})            // kind → running job
    readonly property bool scanning: !!jobs.devices
    readonly property bool pairingNow: !!jobs.pair
    readonly property bool busy: Object.keys(jobs).length > 0
    signal paired()
    signal forgotten()

    function start() { refresh(); checkAdapter() }
    function refresh() { run("configuration", ["pairing-configuration-json"]) }
    function checkAdapter() {
        const args = ["pairing-compatibility-json"]
        if (adapter) args.push("--adapter", adapter)
        run("compatibility", args)
    }
    function scan() {
        const args = ["pairing-devices-json", "--scan-seconds", "24"]
        if (adapter) args.push("--adapter", adapter)
        status = "Looking for your iPhone…"
        run("devices", args)
    }
    function stopScan() { stop("devices"); status = "" }
    function enableBluetooth() {
        status = "Restarting Bluetooth for iPhone…"
        run("activate", ["pairing-activate-bluez"])
    }
    function pair() {
        const device = devices[selected]
        if (!device || busy) return
        const args = ["pairing-complete", device.mac, "--interactive-agent"]
        const a = device.adapter_path ? String(device.adapter_path).split("/").pop() : adapter
        if (a) args.push("--adapter", a)
        if (!notificationsSupported) args.push("--compatibility-mode")
        if (explicitPairing) args.push("--explicit-pairing")
        if (!device.paired && phoneMac && phoneMac !== device.mac) args.push("--replace-saved-mac", phoneMac)
        transports = ({ map: false, pbap: false, ancs: false })
        passkey = ""
        status = "Pairing with " + (device.name || "iPhone") + "…"
        run("pair", args, true)
    }
    function answer(accepted) {
        const job = jobs.pair || jobs.forget
        if (!confirming || !job) return
        confirming = false
        status = accepted ? "Finishing setup…" : "Canceling…"
        job.send(accepted ? "yes\n" : "no\n")
    }
    function forget() {
        if (!phoneMac || busy) return
        const args = ["pairing-forget", phoneMac, "--interactive-approval"]
        if (phoneAdapter) args.push("--adapter", phoneAdapter)
        status = "Disconnecting your iPhone…"
        run("forget", args, true)
    }

    // ------------------------------------------------------------ plumbing
    function run(kind, args, interactive) {
        stop(kind)
        const job = jobComponent.createObject(pairing, { kind: kind, command: [cli].concat(args), interactive: !!interactive })
        jobs = Object.assign({}, jobs, { [kind]: job })
        job.begin()
    }
    function stop(kind) {
        const job = jobs[kind]
        if (!job) return
        const next = Object.assign({}, jobs); delete next[kind]; jobs = next
        job.abort()
    }
    function streamed(kind, line) {
        let data
        try { data = JSON.parse(line) } catch (e) { return }
        if (data.event === "display" || data.event === "confirmation") {
            passkey = String(data.passkey || "")
            confirming = data.event === "confirmation"
            status = kind === "forget" ? "Confirm disconnecting this iPhone."
                : passkey ? "Make sure this code matches the one on your iPhone." : "Approve the pairing request."
        } else if (data.event === "transports") {
            transports = ({ map: !!data.map, pbap: !!data.pbap, ancs: !!data.ancs })
            status = data.map && data.pbap ? "Messages and contacts are connected. Finishing…" : "Checking the connection…"
        }
    }
    function finished(kind, code, output, diagnostic) {
        if (jobs[kind]) { const next = Object.assign({}, jobs); delete next[kind]; jobs = next }
        if (kind === "pair" || kind === "forget") { confirming = false; passkey = "" }
        let data = null
        const lines = String(output || "").trim().split("\n")
        try { data = JSON.parse(lines[lines.length - 1]) } catch (e) {}
        const failure = code !== 0 || !data || data.error || data.ok === false
        if (kind === "configuration") {
            if (data && typeof data.configured === "boolean") {
                configured = data.configured
                phoneMac = data.saved ? String(data.mac || "") : ""
                phoneAdapter = data.saved ? String(data.adapter || "") : ""
                bonded = data.bonded !== false
            }
        } else if (kind === "compatibility") {
            checkedAdapter = true
            if (data && !data.error) {
                hardwareSupported = data.hardware_supported !== false
                pairingReady = data.pairing_ready !== false
                notificationsSupported = data.notifications_supported === true
                bluezReady = data.bearer_api_active === true
                explicitPairing = data.explicit_pairing_default === true
                adapter = String(data.adapter || adapter)
                issue = String(data.issue || "")
            } else {
                hardwareSupported = false
                issue = (data && data.error) || diagnostic || "Bluetooth isn't available on this computer."
            }
        } else if (kind === "devices") {
            if (Array.isArray(data)) {
                devices = data.filter((d) => d && typeof d.mac === "string")
                selected = devices.length ? 0 : -1
                status = devices.length ? "" : "No iPhone found. Keep Settings › Bluetooth open on your iPhone, then try again."
            } else status = (data && data.error) || diagnostic || "Couldn't search for devices."
        } else if (kind === "activate") {
            status = failure ? ((data && data.error) || diagnostic || "Bluetooth wasn't restarted.") : ""
            if (!failure) { bluezReady = true; checkAdapter() }
        } else if (kind === "pair") {
            if (failure || !data.device) status = (data && data.error) || diagnostic || "Pairing didn't finish. Try again."
            else {
                configured = true
                bonded = true
                phoneMac = String(data.device.mac)
                status = ""
                paired()
            }
            refresh()
        } else if (kind === "forget") {
            if (failure) status = (data && data.error) || diagnostic || "Couldn't disconnect the iPhone."
            else {
                configured = false; phoneMac = ""; phoneAdapter = ""; devices = []; selected = -1
                status = "Also choose Forget This Device for this computer on your iPhone."
                forgotten()
            }
            refresh()
        }
    }

    component Job: Item {
        id: job
        property string kind
        property var command: []
        property bool interactive: false
        property int consumed: 0
        property bool aborted: false
        property int code: -1
        property bool exited: false
        property bool outDone: false
        property bool errDone: false
        function begin() { proc.running = true; deadline.start() }
        function send(text) { proc.write(text) }
        function abort() { aborted = true; proc.signal(15); job.destroy(1000) }
        function complete() {
            if (aborted || !exited || !outDone || !errDone) return
            deadline.stop()
            pairing.finished(kind, code, out.text, err.text.trim())
            job.destroy()
        }
        Process {
            id: proc
            command: job.command
            stdinEnabled: job.interactive
            stdout: StdioCollector {
                id: out
                waitForEnd: false
                onTextChanged: {
                    if (!job.interactive || job.aborted) return
                    let end = text.indexOf("\n", job.consumed)
                    while (end >= 0) {
                        pairing.streamed(job.kind, text.slice(job.consumed, end))
                        job.consumed = end + 1
                        end = text.indexOf("\n", job.consumed)
                    }
                }
                onStreamFinished: { job.outDone = true; job.complete() }
            }
            stderr: StdioCollector { id: err; onStreamFinished: { job.errDone = true; job.complete() } }
            onExited: (c) => { job.code = c; job.exited = true; job.complete() }
        }
        // Pairing waits on people and radios; everything else answers quickly.
        Timer {
            id: deadline
            interval: job.interactive ? 600000 : job.kind === "devices" ? 90000 : 60000
            onTriggered: {
                proc.signal(9)
                if (!job.aborted) pairing.finished(job.kind, -1, "", "BlueFerry didn't answer in time.")
                job.aborted = true
            }
        }
    }
    Component { id: jobComponent; Job {} }
}
