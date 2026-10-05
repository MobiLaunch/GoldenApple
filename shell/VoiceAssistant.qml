// Citron Live: summoned by ⇧⌘Space or Citron Intelligence → Talk.
// A focused, dismissible Liquid Glass surface, never a background hot mic.
// The Python helper owns ephemeral mic/speaker streams; the QML side only
// receives level/status/transcription, not raw audio or API credentials.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "ui/theme"
import "components"

PanelWindow {
    id: citron
    property bool open: false
    property bool micMuted: false
    property bool everReady: false
    property string phase: "connecting"
    property string errorText: ""
    property string youSaid: ""
    property string citronSaid: ""
    property real soundLevel: 0
    readonly property string helper: decodeURIComponent(
        Qt.resolvedUrl("ui/intelligence/live.py").toString().replace("file://", ""))

    function present() {
        if (open) { textEntry.forceActiveFocus(); return }
        open = true
        phase = "connecting"
        everReady = false
        errorText = ""
        micMuted = false
        soundLevel = 0
        youSaid = ""
        citronSaid = ""
        voiceProc.running = true
    }
    function dismiss() {
        if (!open) return
        open = false
        voiceProc.running = false
        soundLevel = 0
        textEntry.text = ""
    }
    function toggle() { if (open) dismiss(); else present() }
    function sendText() {
        const text = textEntry.text.trim()
        if (!text || !voiceProc.running || !everReady) return
        voiceProc.write(JSON.stringify({ action: "text", text: text }) + "\n")
        textEntry.text = ""
    }
    function toggleMic() {
        if (!voiceProc.running || !everReady) return
        micMuted = !micMuted
        voiceProc.write(JSON.stringify({action: "mute", enabled: micMuted}) + "\n")
        if (micMuted) soundLevel = 0
    }
    function readEvent(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.event === "status") {
            phase = msg.mode
            if (msg.mode === "listening") everReady = true
        } else if (msg.event === "level") {
            soundLevel = micMuted ? 0 : Math.max(0, Math.min(1, Number(msg.value) || 0))
        } else if (msg.event === "transcript") {
            if (msg.role === "user") youSaid = msg.text
            if (msg.role === "assistant") citronSaid = msg.text
        } else if (msg.event === "notice") {
            citronSaid = msg.text
        } else if (msg.event === "error") {
            phase = "error"
            errorText = msg.text
        }
    }

    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "citron-intelligence-voice"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Transparent everywhere else: do not swallow clicks on underlying apps.
    Item { id: emptyMask; width: 0; height: 0; visible: false }
    mask: Region { item: citron.open ? bubble : emptyMask }

    IpcHandler {
        target: "citron"
        function toggle(): void { citron.toggle() }
        function open(): void { citron.present() }
        function close(): void { citron.dismiss() }
    }

    Process {
        id: voiceProc
        command: ["python3", citron.helper]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => citron.readEvent(line)
        }
        onExited: {
            if (!citron.open) return
            if (citron.phase !== "error" && citron.phase !== "stopped") {
                citron.phase = "error"
                citron.errorText = "Voice disconnected. Select Retry to reconnect."
            }
        }
    }

    Rectangle {
        id: bubble
        objectName: "citronVoiceBubble"
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 88 }
        width: Math.min(530, citron.width - 28)
        height: 218
        radius: 35
        color: "transparent"
        focus: citron.open
        Keys.onEscapePressed: citron.dismiss()

        Glass {
            anchors.fill: parent
            role: "regular"
            radius: bubble.radius
            tint: Theme.dark ? "#d2242537" : "#e4e8e8fa"
            shadow: "#68000000"
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: bubble.radius - 1
            color: "transparent"
            border { width: 1; color: Theme.dark ? "#60c7c3f9" : "#c2ffffff" }
        }

        // Responsive, refractive-looking Siri-style light bloom.
        Item {
            id: orb
            objectName: "citronVoiceOrb"
            width: 104 + citron.soundLevel * 14
            height: width
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 10 }
            scale: citron.phase === "speaking" ? 1.05 : 1
            Behavior on width { NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 12
                height: width
                radius: width / 2
                color: "transparent"
                border { width: 1.5; color: "#4ec4bdfc" }
                opacity: citron.phase === "connecting" ? 0.4 : 0.3 + citron.soundLevel * 0.65
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.00; color: citron.phase === "muted" ? "#8d92a0" : "#c9f7ff" }
                    GradientStop { position: 0.30; color: citron.phase === "muted" ? "#626878" : "#68a5ff" }
                    GradientStop { position: 0.66; color: citron.phase === "muted" ? "#535d70" : "#b182f1" }
                    GradientStop { position: 1.00; color: citron.phase === "error" ? "#e76b76" : "#553e9a" }
                }
            }
            Rectangle {
                id: shine
                width: orb.width * 0.73
                height: orb.height * 0.43
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 4 }
                radius: width / 2
                rotation: -18
                color: "#aaffffff"
                opacity: 0.24
            }
            Rectangle {
                width: orb.width * 0.65
                height: orb.height * 0.27
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 7 }
                radius: width / 2
                rotation: 14
                color: "#d14968fa"
                opacity: 0.45
            }
            Rectangle {
                anchors.centerIn: parent
                width: orb.width * 0.64
                height: width
                radius: width / 2
                color: "#30ffffff"
                opacity: citron.phase === "speaking" ? .75 : .3
                SequentialAnimation on opacity {
                    running: citron.open && !Theme.reduceMotion &&
                        (citron.phase === "listening" || citron.phase === "speaking")
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.12; duration: 850; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.72; duration: 1000; easing.type: Easing.InOutSine }
                }
            }
        }

        readonly property string prompt: citron.phase === "error" ? "Couldn't start voice"
            : citron.phase === "connecting" ? "Connecting to Gemini Live…"
            : citron.phase === "speaking" ? "Citron is speaking"
            : citron.micMuted ? "Microphone muted"
            : citron.phase === "listening" ? "I'm listening"
            : "Ready to talk"
        Text {
            id: status
            anchors { top: orb.bottom; horizontalCenter: parent.horizontalCenter; topMargin: 4 }
            text: bubble.prompt
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
        }
        Text {
            id: transcript
            anchors { top: status.bottom; horizontalCenter: parent.horizontalCenter; topMargin: 4 }
            width: parent.width - 52
            horizontalAlignment: Text.AlignHCenter
            maximumLineCount: 1
            elide: Text.ElideRight
            text: citron.errorText || citron.citronSaid || citron.youSaid ||
                "Talk naturally, ask follow-ups, or interrupt at any time"
            color: citron.phase === "error" ? "#ff666a" : Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12 }
        }
        Rectangle {
            id: controls
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 11 }
            height: 36
            radius: 17
            color: Theme.dark ? "#1cffffff" : "#48ffffff"
            border { width: 0.5; color: Theme.separator }

            Rectangle {
                id: micToggle
                width: 76
                height: 30
                radius: 15
                x: 3; y: 3
                color: citron.micMuted ? "#32ff453a" : (Theme.dark ? "#25ffffff" : "#30e0e0ef")
                Text {
                    anchors.centerIn: parent
                    text: citron.micMuted ? "Unmute" : "Mute"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; onClicked: citron.toggleMic() }
            }

            TextInput {
                id: textEntry
                objectName: "citronVoiceText"
                anchors { left: micToggle.right; right: send.left; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 8 }
                clip: true
                color: Theme.label
                selectionColor: "#55a992ff"
                font { family: Theme.fontUi; pixelSize: 13 }
                enabled: citron.everReady && citron.phase !== "error"
                onAccepted: citron.sendText()
                Keys.onEscapePressed: citron.dismiss()
                Text {
                    visible: !textEntry.text && !textEntry.activeFocus
                    text: "Or type your question…"
                    color: Theme.tertiaryLabel
                    font: textEntry.font
                }
            }

            Rectangle {
                id: send
                anchors { right: endButton.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: 42
                height: 28; radius: 14
                color: Theme.dark ? "#4f8f64df" : "#548474d6"
                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: "white"
                    font { family: Theme.fontUi; pixelSize: 17; weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; onClicked: citron.sendText() }
            }

            Rectangle {
                id: endButton
                anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                width: 58; height: 29; radius: 14
                color: Theme.dark ? "#5bff453a" : "#e6ffdfdd"
                Text {
                    anchors.centerIn: parent
                    text: "End"
                    color: Theme.dark ? "#fff" : "#991d1d"
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                }
                MouseArea { anchors.fill: parent; onClicked: citron.dismiss() }
            }
        }

        Rectangle {
            visible: citron.phase === "error"
            anchors { right: parent.right; top: parent.top; margins: 16 }
            width: 55; height: 28; radius: 14
            color: Theme.dark ? "#36ffffff" : "#7cffffff"
            Text { anchors.centerIn: parent; text: "Retry"; color: Theme.label; font.pixelSize: 12 }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    voiceProc.running = false
                    citron.phase = "connecting"
                    citron.errorText = ""
                    citron.everReady = false
                    voiceProc.running = true
                }
            }
        }
    }
}
