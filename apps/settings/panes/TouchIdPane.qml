// Touch ID & Password: fingerprints on the computer's reader (fprintd), as on
// the Mac. Up to three fingers; adding one follows the reader stage by stage
// ("lift and rest your finger"). A finger unlocks the lock screen and, if
// chosen, answers sudo and system password prompts (touchid-helper.py, as
// an administrator). After a restart the password is needed to log in.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "touchid"
    headerTint: "#ff375f"
    headerTitle: "Touch ID & Password"
    headerText: "Use your fingerprint to unlock this computer and, if you like, for administrator prompts. After a restart your password is required."

    readonly property string user: Quickshell.env("USER") ?? ""
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../touchid-helper.py").toString().replace("file://", ""))
    // loading | ready | noreader | missing (fprintd not installed)
    property string status: "loading"
    property string device: ""
    property var fingers: []              // enrolled, e.g. "right-index-finger"
    property bool admin: false
    property bool adminBusy: false
    property string error: ""
    readonly property int most: 3
    readonly property var order: ["right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
        "right-middle-finger", "left-middle-finger", "right-ring-finger", "left-ring-finger", "right-little-finger", "left-little-finger"]
    function fingerName(f) { return f.split("-").map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" ") }

    // fprintd-list: the reader, and the fingers enrolled on it.
    function parse(out, code) {
        if (/not found|No such file/i.test(out) && code !== 0) { status = "missing"; return }
        if (/No devices available/i.test(out) || (code !== 0 && !/Fingerprints for user|has no fingers/.test(out))) { status = "noreader"; return }
        const dev = out.match(/(?:Fingerprints for user \S+ on|has no fingers enrolled for) (.+?)(?: \(\w+\))?[:.]?\s*$/m)
        device = dev ? dev[1] : ""
        fingers = out.split("\n").map((l) => (l.match(/^\s*-\s*#\d+:\s*(\S+)/) ?? [])[1]).filter((f) => f)
        status = "ready"
    }
    function load() {
        sys.run(["sh", "-c", "fprintd-list \"$1\" 2>&1", "sh", user], (out, code) => parse(out, code))
        sys.run(["python3", helper, "status"], (out) => { try { admin = JSON.parse(out).admin } catch (e) {} })
    }
    Component.onCompleted: load()

    // ------------------------------------------------------------ adding one
    property string enrolling: ""         // the finger being added
    property int stage: 0
    property int stages: 10               // the reader says how many (busctl), else about ten
    property string prompt: ""
    function add() {
        const f = order.find((o) => !fingers.includes(o))
        if (!f || enroller.running) return
        error = ""; stage = 0; prompt = "Rest your finger on the reader"
        enrolling = f
        sys.run(["sh", "-c", "busctl get-property net.reactivated.Fprint /net/reactivated/Fprint/Device/0 net.reactivated.Fprint.Device num-enroll-stages 2>/dev/null"],
                (out) => { const n = parseInt((out.split(" ")[1] ?? "")); if (n > 0) stages = n })
        enroller.command = ["fprintd-enroll", "-f", f, user]
        enroller.running = true
    }
    function cancel() { enrolling = ""; enroller.running = false }
    Process {
        id: enroller
        stdout: SplitParser { onRead: (line) => pane.enrollLine(line) }
        stderr: SplitParser { onRead: (line) => { if (line.trim()) pane.error = line.trim() } }
        onExited: (code) => {
            if (pane.enrolling && code !== 0 && !pane.error) pane.error = "The fingerprint couldn't be added."
            pane.enrolling = ""
            pane.load()
        }
    }
    function enrollLine(line) {
        const r = (line.match(/Enroll result: (\S+)/) ?? [])[1]
        if (!r) return
        if (r === "enroll-stage-passed") { stage = Math.min(stages - 1, stage + 1); prompt = "Lift and rest your finger again" }
        else if (r === "enroll-retry-scan" || r === "enroll-swipe-too-short") prompt = "Try again, resting your finger a little longer"
        else if (r === "enroll-finger-not-centered") prompt = "Rest the middle of your finger on the reader"
        else if (r === "enroll-remove-and-retry") prompt = "Lift your finger and try again"
        else if (r === "enroll-completed") { stage = stages; prompt = "Done" }
        else if (r === "enroll-duplicate") error = "That finger has already been added."
        else if (r === "enroll-data-full") error = "The reader has no room for another fingerprint."
        else if (r === "enroll-disconnected") error = "The reader was disconnected."
        else if (r === "enroll-failed" || r === "enroll-unknown-error") error = "The fingerprint couldn't be added. Try again."
    }
    function remove(f) {
        error = ""
        sys.run(["sh", "-c", "fprintd-delete \"$1\" -f \"$2\" 2>&1", "sh", user, f], (out, code) => {
            if (code !== 0) error = "The fingerprint couldn't be removed."
            load()
        })
    }
    // sudo and system prompts: as an administrator (pkexec), like Software Update.
    function setAdmin(on) {
        adminBusy = true; error = ""
        sys.run(["sh", "-c", "if sudo -n true >/dev/null 2>&1; then exec sudo -n \"$1\" \"$2\"; else exec pkexec \"$1\" \"$2\"; fi",
                 "sh", helper, on ? "enable" : "disable"], (out, code) => {
            adminBusy = false
            if (code !== 0) error = on ? "Touch ID couldn't be turned on for administrator prompts." : "Touch ID couldn't be turned off for administrator prompts."
            try { admin = JSON.parse(out.trim().split("\n").pop()).admin } catch (e) { load() }
        })
    }

    Group {
        visible: pane.status === "noreader" || pane.status === "missing"
        SetRow {
            title: pane.status === "missing" ? "Fingerprint support isn't installed" : "No fingerprint reader found"
            subtitle: pane.status === "missing" ? "Install fprintd to use Touch ID." : "If this computer has one, it may not be supported yet (libfprint)."
            symbol: "touchid"; symbolTint: "#8e8e93"
        }
    }

    // The fingers, and adding one.
    Group {
        objectName: "touchIdFingers"
        visible: pane.status === "ready" && !pane.enrolling
        title: "Fingerprints"
        Row {
            x: 14; height: 132
            spacing: 22
            Repeater {
                model: pane.fingers
                delegate: Item {
                    id: finger
                    required property string modelData
                    width: 92; height: 132
                    Rectangle {
                        id: disc
                        y: 14; width: 72; height: 72; radius: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.dark ? "#3a3a3c" : "#e5e5ea"
                        Symbol { anchors.centerIn: parent; name: "touchid"; tone: "accent"; size: 40 }
                    }
                    // Remove, top left of the disc, on hover.
                    Rectangle {
                        x: disc.x - 4; y: disc.y - 4; width: 22; height: 22; radius: 11
                        color: Theme.dark ? "#5a5a5e" : "#d1d1d6"
                        opacity: fingerHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Symbol { anchors.centerIn: parent; name: "xmark"; size: 9 }
                        TapHandler { onTapped: pane.remove(finger.modelData) }
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; top: disc.bottom; topMargin: 8 }
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: pane.fingerName(finger.modelData)
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    HoverHandler { id: fingerHover }
                }
            }
            Item {
                visible: pane.fingers.length < pane.most
                width: 92; height: 132
                Rectangle {
                    id: addDisc
                    y: 14; width: 72; height: 72; radius: 36
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: addHover.hovered ? Theme.fill : "transparent"
                    border { width: 1.5; color: Theme.dark ? "#5a5a5e" : "#c7c7cc" }
                    Symbol { anchors.centerIn: parent; name: "plus"; tone: "accent"; size: 22 }
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; top: addDisc.bottom; topMargin: 8 }
                    text: "Add Fingerprint"
                    color: Theme.accent
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
                HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: pane.add() }
            }
        }
    }

    // Adding one: the reader, stage by stage.
    Group {
        objectName: "touchIdEnrolling"
        visible: !!pane.enrolling
        title: pane.enrolling ? "Add " + pane.fingerName(pane.enrolling) : ""
        Item {
            width: parent.width; height: 210
            Shape {
                id: ring
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18; width: 120; height: 120
                preferredRendererType: Shape.CurveRenderer
                property real done: pane.stages > 0 ? pane.stage / pane.stages : 0
                Behavior on done { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                ShapePath {
                    strokeColor: Theme.dark ? "#3a3a3c" : "#e5e5ea"; strokeWidth: 6; fillColor: "transparent"
                    PathAngleArc { centerX: 60; centerY: 60; radiusX: 56; radiusY: 56; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: "#ff375f"; strokeWidth: 6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 60; centerY: 60; radiusX: 56; radiusY: 56; startAngle: -90; sweepAngle: 360 * ring.done }
                }
                Symbol { anchors.centerIn: parent; name: "touchid"; tone: "accent"; size: 56 }
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: ring.bottom; topMargin: 14 }
                text: pane.prompt
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
            }
            Button {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                text: "Cancel"
                onClicked: pane.cancel()
            }
        }
    }

    Text {
        visible: !!pane.error
        width: parent.width
        wrapMode: Text.WordWrap
        text: pane.error
        color: Theme.dark ? "#ff453a" : "#ff3b30"
        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
    }

    Group {
        visible: pane.status === "ready"
        title: "Use Touch ID for"
        SetRow {
            title: "Unlocking this computer"
            subtitle: pane.fingers.length ? "" : "Add a fingerprint first."
            Switch {
                checked: pane.sys.prefs.touchId?.unlock ?? true
                onToggled: (on) => pane.sys.setPref(["touchId", "unlock"], on)
            }
        }
        SetRow {
            title: "Administrator prompts and sudo"
            subtitle: "Asks for your finger first; your password still works."
            Switch {
                checked: pane.admin
                enabled_: !pane.adminBusy
                onToggled: (on) => pane.setAdmin(on)
            }
        }
    }
}
