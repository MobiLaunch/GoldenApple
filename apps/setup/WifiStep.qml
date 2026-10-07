// Select Your Wi-Fi Network: networks from NetworkManager, strongest first;
// secured ones ask for their password in place. Wired or already online, it
// says so. "Other Network Options" lets you go on without a network.
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib"
import "../lib/theme"

StepFrame {
    id: step
    symbol: "wifi"
    title: "Select Your Wi-Fi Network"
    text: online ? "This computer is connected to the internet" + (via ? " via " + via : "") + "." : "Choose a network to connect to the internet."
    secondaryText: online ? "" : "Set Up Later"
    onSecondary: next()

    property var networks: []        // {ssid, signal, secure, active}
    property bool scanning: scan.running
    property bool online: false
    property string via: ""
    property string joining: ""      // network asking for a password / connecting
    property bool connecting: connect.running
    property string error: ""

    // nmcli -t escapes ":" in fields as "\:".
    function fields(line) {
        const out = []; let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (c === ":") { out.push(cur); cur = ""; continue }
            cur += c
        }
        out.push(cur)
        return out
    }
    function refresh() { scan.running = true; netState.running = true }
    Component.onCompleted: refresh()
    Timer { interval: 8000; running: !step.connecting && !step.joining; repeat: true; onTriggered: step.refresh() }

    Process {
        id: scan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const best = {}
                for (const line of text.split("\n")) {
                    if (!line.trim()) continue
                    const f = step.fields(line)
                    const ssid = f[1]
                    if (!ssid) continue
                    const n = { ssid: ssid, signal: Number(f[2]) || 0, secure: !!f[3] && f[3] !== "--", active: f[0] === "*" }
                    if (!best[ssid] || n.signal > best[ssid].signal || n.active) best[ssid] = n
                }
                step.networks = Object.values(best).sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
            }
        }
    }
    Process {
        id: netState
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                let via = "", on = false
                for (const line of text.split("\n")) {
                    const f = step.fields(line)
                    if (f[1] !== "connected") continue
                    if (f[0] === "ethernet") { on = true; via = via || "Ethernet" }
                    if (f[0] === "wifi") { on = true; via = f[2] }
                }
                step.online = on; step.via = via
            }
        }
    }
    Process {
        id: connect
        property string ssid
        property string password
        command: password ? ["nmcli", "device", "wifi", "connect", ssid, "password", password] : ["nmcli", "device", "wifi", "connect", ssid]
        stderr: StdioCollector { id: connectErr }
        onExited: (code) => {
            if (code === 0) { step.joining = ""; step.error = ""; step.refresh() }
            else step.error = connectErr.text.includes("Secrets were required") || connectErr.text.includes("password")
                              ? "The password is incorrect." : "Couldn't join this network."
        }
    }
    function join(n, password) {
        error = ""
        connect.ssid = n.ssid
        connect.password = password ?? ""
        connect.running = true
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.dark ? "#14ffffff" : "#8cffffff"
        border { width: 0.5; color: Theme.separator }
        ListView {
            id: list
            anchors { fill: parent; margins: 4 }
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: step.networks
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool asking: step.joining === modelData.ssid
                width: list.width
                height: asking ? 76 : 34
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                clip: true
                Rectangle {
                    width: parent.width; height: 34; radius: 7
                    color: Theme.dark ? "#ffffff" : "#000000"
                    opacity: row.asking ? 0.08 : wh.hovered ? 0.05 : 0
                }
                Symbol {
                    x: 10; y: 9; visible: row.modelData.active
                    name: "checkmark"; tone: "accent"; size: 14
                }
                Text {
                    x: 32; y: 9; width: parent.width - 110; elide: Text.ElideRight
                    text: row.modelData.ssid
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: row.modelData.active ? Font.DemiBold : Font.Normal }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 12 }
                    y: 9; spacing: 8
                    Symbol { visible: row.modelData.secure; name: "lock"; size: 13; opacity: 0.7 }
                    Symbol { name: "wifi"; size: 15; opacity: 0.35 + 0.65 * Math.min(1, row.modelData.signal / 80) }
                }
                // Password, in place
                Row {
                    visible: row.asking
                    x: 32; y: 40
                    spacing: 8

                    TextField {
                        id: pw
                        width: row.width - 32 - 90
                        height: 28
                        password: true
                        placeholder: step.error || "Password"
                        onAccepted: step.join(row.modelData, text)
                        input.Keys.onEscapePressed: step.joining = ""
                        Component.onCompleted: if (row.asking) Qt.callLater(() => pw.input.forceActiveFocus())
                    }

                    Button {
                        width: 70
                        height: 28
                        text: step.connecting ? "Joining…" : "Join"
                        prominent: true
                        enabled: !step.connecting && pw.text.length > 0
                        onClicked: step.join(row.modelData, pw.text)
                    }
                }
                HoverHandler { id: wh }
                TapHandler {
                    enabled: !row.asking
                    onTapped: {
                        if (row.modelData.active) return
                        step.error = ""
                        if (row.modelData.secure) { step.joining = row.modelData.ssid; Qt.callLater(() => pw.input.forceActiveFocus()) }
                        else step.join(row.modelData)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: step.scanning ? "Looking for networks…" : step.online ? "No Wi-Fi networks nearby." : "No Wi-Fi networks found."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }
        }
        Scroller { flickable: list }
    }
}
