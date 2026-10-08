// Citron Live: summoned by ⇧⌘Space or Citron Intelligence → Talk.
// As Siri on the Mac: a glow traces the screen's edges, Citron's orb floats
// over a slim glass capsule (mic, a field to type into, send, close), and
// live captions sit between them. Focused and dismissible, never a
// background hot mic. The Python helper owns ephemeral mic/speaker streams;
// the QML side only receives level/status/transcription, not raw audio or
// API credentials.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "ui/theme"
import "components"
import "ui" as Shared

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
    // What the orb does: it listens, thinks while connecting, speaks.
    readonly property string orbMode: phase === "error" ? "error" : micMuted ? "muted"
        : phase === "connecting" ? "thinking" : phase === "speaking" ? "speaking" : "listening"

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
        youSaid = ""
        citronSaid = ""
        errorText = ""
        micMuted = false
        everReady = false
        phase = "stopped"
        textEntry.text = ""
    }
    function toggle() { if (open) dismiss(); else present() }
    function retry() {
        voiceProc.running = false
        phase = "connecting"
        errorText = ""
        everReady = false
        Qt.callLater(() => { if (citron.open) voiceProc.running = true })
    }
    function sendText() {
        const text = textEntry.text.trim()
        if (!text || !voiceProc.running || !everReady) return
        voiceProc.write(JSON.stringify({ action: "text", text: text }) + "\n")
        textEntry.text = ""
    }
    function toggleMic() {
        if (phase === "error") { retry(); return }
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
            if (msg.role === "user") { youSaid = msg.text; citronSaid = "" }
            if (msg.role === "assistant") citronSaid = msg.text
        } else if (msg.event === "notice") {
            citronSaid = msg.text
        } else if (msg.event === "error") {
            phase = "error"
            errorText = msg.text
        }
    }

    // Stays mapped while it fades out.
    property real shown: open ? 1 : 0
    Behavior on shown { NumberAnimation { duration: Theme.reduceMotion ? 1 : (citron.open ? 420 : 240); easing.type: Easing.OutCubic } }
    visible: open || shown > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-citron"
    // What its glass bends: the desktop under it.
    DesktopBackdrop { surface: citron; namespace: "gg-citron" }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Transparent everywhere else: do not swallow clicks on underlying apps.
    Item { id: emptyMask; width: 0; height: 0; visible: false }
    mask: Region { item: citron.open ? stage : emptyMask }

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

    // The edge glow: Citron's colours flowing round the screen's edges,
    // brighter as you speak. Kept faint (HyprGlass leaves it clear).
    property real flow: 0
    FrameAnimation {
        running: citron.visible && !Theme.reduceMotion
        onTriggered: citron.flow = (citron.flow + frameTime * (citron.phase === "speaking" ? 0.22 : 0.12)) % 1
    }
    Item {
        id: glow
        anchors.fill: parent
        opacity: citron.shown * (citron.orbMode === "muted" ? 0.35 : 0.75 + orb.energy * 0.25)
        visible: opacity > 0.01
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32 }
        readonly property var hues: orb.hues
        readonly property real band: 10 + orb.energy * 8
        // One edge: a band twice its length, repeating the colours once,
        // sliding along it, so the flow never jumps.
        component Edge: Item {
            property bool across: true
            property real offset: 0
            clip: true
            opacity: 0.42
            Rectangle {
                width: parent.across ? parent.width * 2 : parent.width
                height: parent.across ? parent.height : parent.height * 2
                x: parent.across ? -parent.offset * parent.width : 0
                y: parent.across ? 0 : -parent.offset * parent.height
                gradient: Gradient {
                    orientation: parent.parent.across ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: 0.0; color: glow.hues[0] }
                    GradientStop { position: 0.125; color: glow.hues[1] }
                    GradientStop { position: 0.25; color: glow.hues[2] }
                    GradientStop { position: 0.375; color: glow.hues[3] }
                    GradientStop { position: 0.5; color: glow.hues[0] }
                    GradientStop { position: 0.625; color: glow.hues[1] }
                    GradientStop { position: 0.75; color: glow.hues[2] }
                    GradientStop { position: 0.875; color: glow.hues[3] }
                    GradientStop { position: 1.0; color: glow.hues[0] }
                }
            }
        }
        Edge { anchors { left: parent.left; right: parent.right; top: parent.top } height: glow.band; across: true; offset: citron.flow }
        Edge { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: glow.band; across: true; offset: 1 - citron.flow }
        Edge { anchors { top: parent.top; bottom: parent.bottom; left: parent.left } width: glow.band; across: false; offset: 1 - citron.flow }
        Edge { anchors { top: parent.top; bottom: parent.bottom; right: parent.right } width: glow.band; across: false; offset: citron.flow }
    }

    // The orb, the captions and the capsule, above the Dock.
    Item {
        id: stage
        objectName: "citronVoiceBubble"
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 96 }
        width: Math.min(560, citron.width - 28)
        height: orb.height + captions.height + capsule.height + 24
        opacity: citron.shown
        transform: Translate { y: (1 - citron.shown) * 18 }
        focus: citron.open
        Keys.onEscapePressed: citron.dismiss()

        Shared.CitronOrb {
            id: orb
            objectName: "citronVoiceOrb"
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            width: 136; height: 136
            mode: citron.orbMode
            level: citron.soundLevel
            running: citron.visible
            scale: 0.6 + 0.4 * citron.shown
        }

        // Live captions: what Citron says, else what you said, else the state.
        Column {
            id: captions
            anchors { top: orb.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
            width: parent.width - 40
            spacing: 2
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: citron.phase === "error" ? "Couldn't start voice"
                    : citron.phase === "connecting" ? "Connecting…"
                    : citron.phase === "speaking" ? "" : citron.micMuted ? "Microphone off" : "Listening…"
                visible: text !== ""
                color: "white"
                font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#90000000"; shadowBlur: 0.6; shadowVerticalOffset: 1 }
            }
            Text {
                id: caption
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: citron.errorText || citron.citronSaid || (citron.youSaid ? "“" + citron.youSaid + "”" : "")
                visible: text !== ""
                color: citron.phase === "error" ? "#ffb3b5" : "white"
                font { family: Theme.fontUi; pixelSize: citron.citronSaid ? 16 : 14; weight: citron.citronSaid ? Font.Medium : Font.Normal }
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#a0000000"; shadowBlur: 0.7; shadowVerticalOffset: 1 }
            }
        }

        // The capsule: mic, a field to type into, send, close.
        Item {
            id: capsule
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            width: parent.width
            height: 50
            Glass {
                anchors.fill: parent
                role: "regular"
                radius: height / 2
                tint: Theme.dark ? "#c8202230" : "#d8f2f2fa"
                shadow: "#50000000"
            }

            component RoundButton: Rectangle {
                id: rb
                property string symbol
                property color fill: Theme.dark ? "#26ffffff" : "#14000000"
                property string tone: "auto"
                signal clicked()
                width: 36; height: 36; radius: 18
                color: fill
                scale: rbTap.pressed && !Theme.reduceMotion ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
                Behavior on color { ColorAnimation { duration: 140 } }
                Shared.Symbol { anchors.centerIn: parent; name: rb.symbol; size: 16; tone: rb.tone }
                MouseArea { id: rbTap; anchors.fill: parent; onClicked: rb.clicked() }
            }

            RoundButton {
                id: micButton
                anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                symbol: citron.phase === "error" ? "arrow-clockwise" : "mic"
                fill: citron.phase === "error" ? (Theme.dark ? "#26ffffff" : "#14000000")
                    : citron.micMuted ? "#ff453a" : Theme.accent
                tone: "white"
                Accessible.name: citron.phase === "error" ? "Retry" : citron.micMuted ? "Unmute" : "Mute"
                onClicked: citron.toggleMic()
                // A slash while muted.
                Rectangle {
                    visible: citron.micMuted && citron.phase !== "error"
                    anchors.centerIn: parent
                    width: 2; height: 22; radius: 1
                    rotation: -45
                    color: "white"
                }
            }

            TextInput {
                id: textEntry
                objectName: "citronVoiceText"
                anchors { left: micButton.right; right: send.left; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 8 }
                clip: true
                color: Theme.label
                selectionColor: "#55a992ff"
                font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                enabled: citron.everReady && citron.phase !== "error"
                focus: citron.open
                onAccepted: citron.sendText()
                Keys.onEscapePressed: citron.dismiss()
                Text {
                    visible: !textEntry.text
                    text: "Ask Citron anything"
                    color: Theme.tertiaryLabel
                    font: textEntry.font
                }
            }

            RoundButton {
                id: send
                anchors { right: close.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                symbol: "arrow-up"
                fill: Theme.accent
                tone: "white"
                width: textEntry.text.trim() ? 36 : 0
                opacity: textEntry.text.trim() ? 1 : 0
                visible: width > 1
                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Accessible.name: "Send"
                onClicked: citron.sendText()
            }

            RoundButton {
                id: close
                anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                symbol: "xmark"
                Accessible.name: "End"
                onClicked: citron.dismiss()
            }
        }
    }
}
