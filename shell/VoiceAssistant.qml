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
import QtQuick.Dialogs
import "ui/intelligence" as AI
import "ui/theme"
import "components"
import "ui" as Shared

PanelWindow {
    id: citron
    property bool open: false
    property bool micMuted: false
    property bool everReady: false
    property string phase: "idle"
    property bool voiceMode: false
    property string tool: "ask"
    property string selectedPhoto: ""
    property string answer: ""
    property var imageResults: []
    property var history: []
    property string responseNote: ""
    property bool responseOpen: false
    readonly property bool aiServiceBusy: aiService.busy
    property string toolTitle: tool === "writing" ? "Writing Tools" : tool === "image" ? "Create an Image" : tool === "edit" ? "Edit a Photo" : "Ask Citron"
    property string errorText: ""
    property string youSaid: ""
    property string citronSaid: ""
    property real soundLevel: 0
    readonly property string helper: decodeURIComponent(
        Qt.resolvedUrl("ui/intelligence/live.py").toString().replace("file://", ""))
    // What the orb does: it listens, thinks while connecting, speaks.
    readonly property string orbMode: aiService.busy ? "thinking" : !voiceMode ? "idle"
        : phase === "error" ? "error" : micMuted ? "muted"
        : phase === "connecting" ? "thinking" : phase === "speaking" ? "speaking" : "listening"

    function present() {
        if (open) { textEntry.forceActiveFocus(); return }
        open = true
        phase = "idle"
        voiceMode = false
        everReady = false
        errorText = ""
        micMuted = false
        soundLevel = 0
        youSaid = ""
        citronSaid = ""
        responseNote = ""
        textEntry.text = ""
        Qt.callLater(() => textEntry.forceActiveFocus())
    }
    function dismiss() {
        if (!open) return
        open = false
        voiceProc.running = false
        aiService.cancel()
        voiceMode = false
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
    function show(kind) {
        if (!open) present()
        if (["ask", "writing", "image", "edit"].includes(kind)) tool = kind
        Qt.callLater(() => textEntry.forceActiveFocus())
    }
    function startVoice() {
        if (voiceMode) return
        voiceMode = true
        phase = "connecting"
        errorText = ""
        everReady = false
        micMuted = false
        voiceProc.running = true
    }
    function chooseTool(kind) {
        if (aiService.busy || !["ask", "writing", "image", "edit"].includes(kind)) return
        tool = kind
        responseOpen = false
        responseNote = ""
        textEntry.text = ""
        Qt.callLater(() => textEntry.forceActiveFocus())
    }
    function sendAI() {
        const q = textEntry.text.trim()
        if (!q || aiService.busy) return
        const task = tool
        if (task === "writing" && !writingSource.text.trim()) {
            responseNote = "Paste or type the text you want to rewrite."
            return
        }
        if (task === "edit" && !selectedPhoto) {
            responseNote = "Choose a photo first."
            return
        }
        const request = { task: task, prompt: q }
        if (task === "ask") {
            request.history = history.slice(-16)
            if (selectedPhoto) request.imagePath = selectedPhoto
        } else if (task === "writing") {
            request.text = writingSource.text
            request.mode = "rewrite"
        } else if (task === "edit") request.imagePath = selectedPhoto
        responseNote = ""
        responseOpen = true
        aiService.send(request)
    }
    function retry() {
        voiceProc.running = false
        phase = "connecting"
        errorText = ""
        everReady = false
        Qt.callLater(() => { if (citron.open) voiceProc.running = true })
    }
    function sendText() {
        const text = textEntry.text.trim()
        if (!text) return
        if (voiceMode && voiceProc.running && everReady) {
            voiceProc.write(JSON.stringify({ action: "text", text: text }) + "\n")
            textEntry.text = ""
        } else sendAI()
    }
    function toggleMic() {
        if (!voiceMode) { startVoice(); return }
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
        function show(kind: string): void { citron.show(kind) }
        function ask(): void { citron.show("ask") }
        function writing(): void { citron.show("writing") }
        function image(): void { citron.show("image") }
        function edit(): void { citron.show("edit") }
    }

    // Reuses the existing keyring-backed Gemini service. Requests are sent on
    // stdin, never through a background HTTP server or a separate app window.
    AI.Service {
        id: aiService
        onCompleted: (action, result) => {
            if (!result.ok) { citron.responseNote = result.error || "Couldn't complete that request."; citron.responseOpen = true; return }
            if (action === "export") {
                citron.responseNote = "Saved: " + result.savedPath
                return
            }
            if (action !== "generate") return
            citron.answer = result.text || ""
            citron.imageResults = result.images || []
            citron.responseOpen = true
            citron.responseNote = result.truncated ? "The answer may be incomplete." : ""
            if (citron.tool === "ask") {
                citron.history = citron.history.concat([
                    { role: "user", text: textEntry.text.trim() },
                    { role: "model", text: citron.answer }
                ]).slice(-20)
            }
            textEntry.text = ""
        }
    }
    FileDialog {
        id: photoPicker
        title: "Choose a photo"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.heic)"]
        onAccepted: citron.selectedPhoto = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))
    }
    FileDialog {
        id: imageSave
        title: "Save Generated Image"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            if (!citron.imageResults.length) return
            aiService.send({action:"export", source: citron.imageResults[0],
                destination: decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))})
        }
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

    // One ambient object, not an application window: no title bar, Dock
    // identity or persistent chat sidebar. Keyboard and screen-reader focus
    // stay in this small region; the desktop underneath remains interactive.
    Item {
        id: stage
        objectName: "citronSystemOverlay"
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
        width: Math.min(610, citron.width - 36)
        height: Math.min(citron.height - 90, content.implicitHeight)
        opacity: citron.shown
        transform: Translate { y: (1 - citron.shown) * 20 }
        focus: citron.open
        Keys.onEscapePressed: citron.dismiss()

        Column {
            id: content
            width: parent.width
            anchors.centerIn: parent
            spacing: 9

            Shared.PrismOrb {
                id: orb
                objectName: "citronPrismaticOrb"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(226, citron.width * 0.31)
                height: width
                mode: citron.orbMode
                level: citron.soundLevel
                running: citron.visible
                scale: 0.90 + 0.10 * citron.shown
                Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 270; easing.type: Easing.OutBack } }
            }

            Column {
                id: captions
                width: parent.width
                spacing: 4
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: citron.voiceMode ?
                        (citron.phase === "error" ? "Microphone unavailable" :
                         citron.phase === "connecting" ? "Connecting voice…" :
                         citron.micMuted ? "Microphone muted" : citron.phase === "speaking" ? "Speaking…" : "Listening…")
                        : citron.aiServiceBusy ? "Thinking…" : citron.toolTitle
                    color: "#f9fafc"
                    font { family: Theme.fontDisplay; pixelSize: Theme.fs(17); weight: Font.DemiBold }
                    layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#88000000"; shadowBlur: 0.9; shadowVerticalOffset: 2 }
                }
                Text {
                    width: parent.width - 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    text: citron.errorText || citron.citronSaid || (citron.youSaid ? "“" + citron.youSaid + "”" : "")
                    visible: !!text
                    color: citron.phase === "error" ? "#ffd0ce" : "#e9edf6"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#99000000"; shadowBlur: 0.9; shadowVerticalOffset: 2 }
                }
            }

            // The answer unfolds only when needed. The orb stays the visual
            // anchor instead of dropping an always-visible chat window.
            Item {
                id: resultArea
                width: parent.width
                height: citron.responseOpen ? Math.min(232, Math.max(94, answerContent.implicitHeight + 28)) : 0
                opacity: citron.responseOpen ? 1 : 0
                visible: height > 1
                Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: 210; easing.type: Easing.OutCubic } }
                Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: 180 } }
                Shared.Glass {
                    anchors.fill: parent
                    role: "menu"; radius: 22
                    tint: "#e9171b26"
                    shadow: "#44000000"
                }
                Column {
                    id: answerContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 15 }
                    spacing: 9
                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            width: parent.width - 86
                            color: "#f5f7fc"
                            text: citron.aiServiceBusy ? "Working on it…" : citron.imageResults.length ? "Your result" : "Response"
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                        }
                        Text {
                            text: citron.aiServiceBusy ? "Cancel" : "Copy"
                            color: "#b8d7ff"
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: citron.aiServiceBusy ? aiService.cancel() : Quickshell.clipboardText = citron.answer
                            }
                        }
                    }
                    Flickable {
                        width: parent.width
                        height: Math.min(156, Math.max(42, answerText.implicitHeight))
                        contentHeight: answerText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        Text {
                            id: answerText
                            width: parent.width
                            wrapMode: Text.WordWrap
                            textFormat: Text.PlainText
                            text: citron.responseNote || citron.answer || (citron.aiServiceBusy ? "Processing your request…" : "")
                            color: "#eef2f8"
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                            lineHeight: 1.22
                        }
                    }
                    Image {
                        visible: citron.imageResults.length > 0
                        source: visible ? "file://" + citron.imageResults[0] : ""
                        width: parent.width; height: visible ? 124 : 0
                        fillMode: Image.PreserveAspectFit; asynchronous: true
                        sourceSize: Qt.size(width * 2, 248)
                    }
                    Text {
                        text: "Save image…"
                        visible: citron.imageResults.length > 0
                        color: "#b8d7ff"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; onClicked: imageSave.open() }
                    }
                }
            }

            // Writing and photo tools appear contextually, not as pages.
            Rectangle {
                id: contextArea
                width: parent.width
                height: citron.tool === "writing" ? 94 : citron.selectedPhoto ? 38 : 0
                visible: height > 0
                radius: 17
                color: "#dc121620"
                border { color: "#35ffffff"; width: 1 }
                TextEdit {
                    id: writingSource
                    visible: citron.tool === "writing"
                    anchors { fill: parent; margins: 14 }
                    color: "#ffffff"; selectionColor: "#637ca8"
                    wrapMode: TextEdit.Wrap
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    clip: true
                    Text {
                        visible: !writingSource.text && writingSource.visible
                        text: "Paste the text you want to refine…"
                        color: "#c8d1df"
                        font: writingSource.font
                    }
                }
                Text {
                    visible: citron.tool !== "writing"
                    anchors { left: parent.left; leftMargin: 15; verticalCenter: parent.verticalCenter }
                    width: parent.width - 75; elide: Text.ElideMiddle
                    text: citron.selectedPhoto.split("/").pop()
                    color: "#edf1f9"; font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Text {
                    visible: citron.tool !== "writing"
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Remove"; color: "#adcfff"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    MouseArea { anchors.fill: parent; onClicked: citron.selectedPhoto = "" }
                }
            }

            Row {
                id: tools
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 7
                component ToolChip: Rectangle {
                    id: chip
                    property string label
                    property string kind
                    radius: 17
                    height: 30
                    width: labelText.implicitWidth + 24
                    color: citron.tool === kind ? "#db34415a" : "#b71a1d27"
                    border { color: citron.tool === kind ? "#7f9fbb" : "#37c2cbd9"; width: 1 }
                    scale: tap.pressed && !Theme.reduceMotion ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: chip.label
                        color: "#f4f6fa"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                    }
                    MouseArea { id: tap; anchors.fill: parent; onClicked: citron.chooseTool(chip.kind) }
                    Accessible.role: Accessible.Button
                    Accessible.name: label
                }
                ToolChip { label: "Ask"; kind: "ask" }
                ToolChip { label: "Write"; kind: "writing" }
                ToolChip { label: "Create"; kind: "image" }
                ToolChip { label: "Edit Photo"; kind: "edit" }
            }

            Item {
                id: capsule
                width: parent.width
                height: 58
                Shared.Glass {
                    anchors.fill: parent; role: "regular"; radius: height / 2
                    tint: "#e81c202a"; shadow: "#5c000000"
                }
                component SmallButton: Rectangle {
                    id: btn
                    property string symbol
                    property string description
                    property color shade: "#2affffff"
                    signal clicked()
                    width: 38; height: 38; radius: 19
                    color: shade
                    scale: mouse.pressed && !Theme.reduceMotion ? 0.93 : 1
                    Behavior on scale { NumberAnimation { duration: 125; easing.type: Easing.OutBack } }
                    Shared.Symbol { anchors.centerIn: parent; name: btn.symbol; size: 17; tone: "white" }
                    MouseArea { id: mouse; anchors.fill: parent; onClicked: btn.clicked() }
                    Accessible.role: Accessible.Button
                    Accessible.name: description
                }
                SmallButton {
                    id: micButton
                    anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    symbol: citron.voiceMode && citron.phase === "error" ? "arrow-clockwise" : "mic"
                    description: !citron.voiceMode ? "Start voice conversation" : citron.micMuted ? "Unmute" : "Mute"
                    shade: citron.voiceMode && !citron.micMuted ? "#b01b4576" : "#30ffffff"
                    onClicked: citron.toggleMic()
                }
                SmallButton {
                    id: photoButton
                    anchors { left: micButton.right; leftMargin: 5; verticalCenter: parent.verticalCenter }
                    symbol: "plus"
                    description: "Attach image"
                    onClicked: photoPicker.open()
                }
                TextInput {
                    id: textEntry
                    objectName: "citronSystemPrompt"
                    anchors { left: photoButton.right; leftMargin: 12; right: send.right; rightMargin: 46; verticalCenter: parent.verticalCenter }
                    height: 29
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: "#ffffff"
                    selectionColor: "#5a79a9"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                    enabled: !citron.aiServiceBusy
                    focus: citron.open
                    onAccepted: citron.sendText()
                    Keys.onEscapePressed: citron.dismiss()
                    Text {
                        visible: !textEntry.text
                        text: citron.tool === "writing" ? "How should I rewrite it?" :
                              citron.tool === "image" ? "Describe an image…" :
                              citron.tool === "edit" ? "Describe the photo edit…" : "Ask anything…"
                        color: "#cbd1dc"
                        font: textEntry.font
                    }
                }
                SmallButton {
                    id: send
                    anchors { right: close.left; rightMargin: 7; verticalCenter: parent.verticalCenter }
                    symbol: "arrow-up"; description: "Send request"
                    shade: textEntry.text.trim() ? "#15579a" : "#38ffffff"
                    onClicked: citron.sendText()
                }
                SmallButton {
                    id: close
                    anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                    symbol: "xmark"; description: "Dismiss Intelligence"
                    onClicked: citron.dismiss()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⌘⇧Space · Esc to close · Microphone starts only when selected"
                color: "#dce3ee"
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#88000000"; shadowBlur: 0.9; shadowVerticalOffset: 2 }
            }
        }
    }
}
