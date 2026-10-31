// Citron Live: summoned by ⇧⌘Space or Citron Intelligence → Talk.
// When summoned, Citron begins listening with an ambient morphing haze.
// Voice never renders text fields, tool chips, mic toggles or send controls.
// Writing Tools keep their editor controls. Text goes to Aion Labs; voice is
// heard and spoken on this computer (voice.py). The Python helper owns ephemeral mic/speaker streams;
// the QML side only receives level/status/transcription, not raw audio or
// API credentials.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "ui/intelligence" as AI
import "ui/theme"
import "components"
import "ui" as Shared
import "ui/intelligence/palette"

PanelWindow {
    id: citron
    property bool open: false
    property bool micMuted: false
    property bool everReady: false
    property string phase: "idle"
    property bool voiceMode: false
    property string tool: "ask"
    property string answer: ""
    property var history: []
    property string pendingPrompt: ""
    property string pendingTool: ""
    property bool restartingVoice: false
    property string responseNote: ""
    property bool responseOpen: false
    readonly property bool aiServiceBusy: aiService.busy
    property string toolTitle: tool === "writing" ? "Writing Tools" : "Ask Citron"
    property string errorText: ""
    property string youSaid: ""
    property string citronSaid: ""
    property real soundLevel: 0
    property real outputLevel: 0
    property real downloaded: 0        // the voice files, fetched on first use (0–1)
    readonly property string helper: decodeURIComponent(
        Qt.resolvedUrl("ui/intelligence/voice.py").toString().replace("file://", ""))
    // What the orb does: it listens, thinks while connecting, speaks.
    readonly property string orbMode: aiService.busy ? "thinking" : !voiceMode ? "idle"
        : phase === "error" ? "error" : micMuted ? "muted"
        : (phase === "connecting" || phase === "thinking" || phase === "downloading") ? "thinking"
        : phase === "speaking" ? "speaking" : "listening"

    function present() {
        if (open) {
            if (voiceMode) stage.forceActiveFocus()
            else textEntry.forceActiveFocus()
            return
        }
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
        Qt.callLater(() => {
            if (!citron.open) return
            if (citron.voiceMode) stage.forceActiveFocus()
            else textEntry.forceActiveFocus()
        })
    }
    function dismiss() {
        if (!open) return
        open = false
        voiceProc.running = false
        outputLevel = 0
        aiService.cancel()
        history = []
        pendingPrompt = ""
        pendingTool = ""
        restartingVoice = false
        voiceWatchdog.stop()
        voiceRestart.stop()
        answer = ""
        responseNote = ""
        responseOpen = false
        tool = "ask"
        writingSource.text = ""
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
    // The global shortcut is voice-first, as a Siri invocation should be.
    // IPC 'ask' and Writing Tools remain explicitly text-first.
    function toggle() {
        if (open) dismiss()
        else { present(); startVoice() }
    }
    function stopVoice() {
        voiceWatchdog.stop()
        voiceRestart.stop()
        restartingVoice = false
        voiceMode = false
        voiceProc.running = false
        everReady = false
        micMuted = false
        soundLevel = 0
        outputLevel = 0
        phase = "idle"
        errorText = ""
    }
    function show(kind) {
        if (!open) present()
        // Every Ask/voice entry point assumes the user wants to speak.
        if (kind === "ask" || kind === "voice") {
            if (voiceMode && phase === "error") retry()
            else startVoice()
            stage.forceActiveFocus()
            return
        }
        // Writing Tools are their own route. Aion Labs' models work with
        // text, so asking for an image explains that, in the text editor.
        if (kind === "writing") {
            if (voiceMode) stopVoice()
            tool = kind
        } else if (kind === "image" || kind === "edit") {
            if (voiceMode) stopVoice()
            tool = "ask"
            responseNote = "Citron works with text: creating and editing images isn't available."
            responseOpen = true
        }
        if (tool === "writing" && !writingSource.text)
            writingSource.text = Quickshell.clipboardText || ""
        Qt.callLater(() => { if (citron.open && !citron.voiceMode) textEntry.forceActiveFocus() })
    }
    function startVoice() {
        if (voiceMode) return
        // A microphone request always starts a conversation, never a
        // writing command left selected from the previous tool.
        tool = "ask"
        voiceMode = true
        outputLevel = 0
        responseOpen = false
        restartingVoice = false
        phase = "connecting"
        errorText = ""
        everReady = false
        micMuted = false
        voiceProc.running = true
        voiceWatchdog.restart()
        Qt.callLater(() => { if (citron.open && citron.voiceMode) stage.forceActiveFocus() })
    }
    function chooseTool(kind) {
        if (aiService.busy || !["ask", "writing"].includes(kind)) return
        if (voiceMode) stopVoice()
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
        answer = ""
        const request = { task: task, prompt: q }
        if (task === "ask") {
            request.history = history.slice(-16)
        } else if (task === "writing") {
            request.text = writingSource.text
            request.mode = "rewrite"
        }
        responseNote = ""
        responseOpen = true
        pendingPrompt = q
        pendingTool = task
        if (!aiService.send(request)) {
            responseNote = "Citron is still completing the previous request."
            pendingPrompt = ""
            pendingTool = ""
        }
    }
    function retry() {
        if (!open || !voiceMode) return
        restartingVoice = true
        voiceWatchdog.stop()
        voiceProc.running = false
        phase = "connecting"
        errorText = ""
        everReady = false
        voiceRestart.restart()
    }
    function sendText() {
        const text = textEntry.text.trim()
        if (!text) return
        if (voiceMode) {
            if (voiceProc.running && everReady && phase !== "error") {
                voiceProc.write(JSON.stringify({ action: "text", text: text }) + "\n")
                textEntry.text = ""
                errorText = ""
            } else {
                errorText = phase === "error" ? "Retry voice to send this message."
                    : "Voice is still connecting. Your message has been kept."
            }
            return
        }
        sendAI()
    }
    function toggleMic() {
        if (!voiceMode) { startVoice(); return }
        if (phase === "error") { retry(); return }
        if (!voiceProc.running || !everReady) return
        micMuted = !micMuted
        voiceProc.write(JSON.stringify({action: "mute", enabled: micMuted}) + "\n")
        if (micMuted) soundLevel = 0
    }
    // Live input/output transcription may repeat a full partial sentence or
    // overlap its previous fragment. Deduplicate without losing word updates.
    function transcriptText(current, incoming, limit) {
        const existing = String(current || "").trim()
        const next = String(incoming || "").trim()
        if (!next) return existing
        if (!existing || next.startsWith(existing)) return next.slice(-limit)
        if (existing === next || existing.endsWith(next)) return existing.slice(-limit)
        const a = existing.toLowerCase(), b = next.toLowerCase()
        for (let n = Math.min(a.length, b.length); n >= 3; n--) {
            if (a.endsWith(b.slice(0, n)))
                return (existing + next.slice(n)).slice(-limit)
        }
        return (existing + " " + next).slice(-limit)
    }
    function readEvent(line) {
        // A just-closed worker may still flush buffered lines. They must not
        // reawaken microphone indicators or overwrite a new text-mode draft.
        if (!open || !voiceMode) return
        let msg
        try { msg = JSON.parse(line) } catch (e) { return }
        if (msg.event === "status") {
            phase = msg.mode
            if (msg.mode !== "speaking") outputLevel = 0
            if (msg.mode === "listening") {
                everReady = true
                voiceWatchdog.stop()
            }
        } else if (msg.event === "download") {
            // Each step of the first-use download shows the session is alive.
            downloaded = Math.max(0, Math.min(1, (Number(msg.done) || 0) / Math.max(1, Number(msg.total) || 1)))
            voiceWatchdog.restart()
        } else if (msg.event === "level") {
            soundLevel = micMuted ? 0 : Math.max(0, Math.min(1, Number(msg.value) || 0))
        } else if (msg.event === "output_level") {
            outputLevel = Math.max(0, Math.min(1, Number(msg.value) || 0))
        } else if (msg.event === "transcript") {
            const fragment = String(msg.text || "").trim()
            if (msg.role === "user" && fragment) {
                if (citronSaid) { youSaid = ""; citronSaid = "" }
                youSaid = transcriptText(youSaid, fragment, 1000)
            }
            if (msg.role === "assistant" && fragment)
                citronSaid = transcriptText(citronSaid, fragment, 1500)
        } else if (msg.event === "timing" && msg.stage === "first_audio") {
            // Timing only: never log utterances or microphone samples.
            console.info("Citron voice: first audio " + Math.max(0, Math.round(Number(msg.ms) || 0))
                         + "ms after speech ended")
        } else if (msg.event === "notice") {
            citronSaid = msg.text
        } else if (msg.event === "error") {
            voiceWatchdog.stop()
            phase = "error"
            errorText = msg.text || "Citron voice could not start."
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
        function open(): void { citron.show("ask") }
        function close(): void { citron.dismiss() }
        function show(kind: string): void { citron.show(kind) }
        function ask(): void { citron.show("ask") }
        function writing(): void { citron.show("writing") }
        function voice(): void { citron.show("ask") }
    }

    // The keyring-backed Aion Labs service. Requests are sent on stdin,
    // never through a background HTTP server or a separate app window.
    AI.Service {
        id: aiService
        onCompleted: (action, result) => {
            if (!citron.open) return
            if (!result.ok) {
                citron.responseNote = result.error || "Couldn't complete that request."
                citron.responseOpen = true
                citron.pendingPrompt = ""
                citron.pendingTool = ""
                return
            }
            if (action !== "generate") return
            citron.answer = result.text || ""
            citron.responseOpen = true
            citron.responseNote = result.truncated ? "The answer may be incomplete." : ""
            // Preserve the prompt actually sent and any new draft typed in
            // the meantime. Otherwise a reply is attached to the wrong turn.
            if (citron.pendingTool === "ask" && citron.pendingPrompt && citron.answer.trim()) {
                citron.history = citron.history.concat([
                    { role: "user", text: citron.pendingPrompt },
                    { role: "assistant", text: citron.answer }
                ]).slice(-20)
            }
            if (textEntry.text.trim() === citron.pendingPrompt) textEntry.text = ""
            citron.pendingPrompt = ""
            citron.pendingTool = ""
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
            if (!citron.open || !citron.voiceMode || citron.restartingVoice) return
            voiceWatchdog.stop()
            if (citron.phase !== "error" && citron.phase !== "stopped") {
                citron.phase = "error"
                citron.errorText = "Voice disconnected. Select Retry to reconnect."
            }
        }
    }

    Timer {
        id: voiceRestart
        interval: 300
        repeat: false
        onTriggered: {
            if (!citron.open || !citron.voiceMode) { citron.restartingVoice = false; return }
            citron.restartingVoice = false
            voiceProc.running = true
            voiceWatchdog.restart()
        }
    }
    Timer {
        id: voiceWatchdog
        interval: 25000
        repeat: false
        onTriggered: {
            if (citron.open && citron.voiceMode && !citron.everReady) {
                citron.phase = "error"
                citron.errorText = "Voice took too long to start. Check your network and microphone, then Retry."
                voiceProc.running = false
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
        height: citron.voiceMode ? Math.min(485, citron.height - 60)
            : Math.min(citron.height - 90, content.implicitHeight)
        opacity: citron.shown
        transform: Translate { y: (1 - citron.shown) * 20 }
        focus: citron.open
        Keys.onEscapePressed: citron.dismiss()

        // This is the ENTIRE summoned voice interface. Capture begins on the
        // user gesture, not passively in the background. Esc stops it.
        Column {
            id: voiceScene
            objectName: "citronVoiceOnlySurface"
            visible: citron.voiceMode
            width: parent.width
            anchors.centerIn: parent
            spacing: 6

            // The visible haze occupies only the central part of its square
            // texture. Reserve a compact visual footprint, while letting the
            // actual 385px field overflow unclipped. The Listening/Speaking
            // caption then stays visually attached to the glass dots instead
            // of floating ~200px below them on desktop screens.
            Item {
                width: parent.width
                height: Math.min(238, citron.height * 0.31)
                AI.CitronBlob {
                id: haze
                objectName: "citronMorphingHaze"
                anchors.centerIn: parent
                width: Math.min(385, stage.width - 14, citron.height * 0.44)
                height: width
                running: citron.open && citron.voiceMode
                mode: citron.orbMode
                inputLevel: citron.soundLevel
                outputLevel: citron.outputLevel
                scale: 0.92 + 0.08 * citron.shown
                Behavior on scale {
                    enabled: !Theme.reduceMotion
                    NumberAnimation { duration: Theme.motion.tap.duration; easing.type: Easing.OutCubic }
                }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: citron.phase === "error" ? "Connection interrupted"
                    : citron.phase === "downloading" ? "Getting Citron's voice ready… " + Math.round(citron.downloaded * 100) + "%"
                    : citron.phase === "connecting" ? "Connecting…"
                    : citron.micMuted ? "Microphone muted"
                    : citron.phase === "speaking" ? "Speaking…"
                    : citron.phase === "thinking" ? "Thinking…"
                    : "Listening…"
                color: Theme.vibrant.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(16); weight: Font.DemiBold }
            }
            Text {
                width: Math.min(parent.width - 26, 500)
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: citron.errorText || citron.citronSaid ||
                    (citron.youSaid ? "“" + citron.youSaid + "”" : "")
                visible: text.length > 0
                color: citron.phase === "error" ? CitronColors.error : Theme.vibrant.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
            }
        }

        // Editor chrome exists only for Writing Tools.
        Column {
            id: content
            visible: !citron.voiceMode
            width: parent.width
            anchors.centerIn: parent
            spacing: 9

            AI.CitronBlob {
                id: orb
                objectName: "citronPrismaticOrb"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(citron.height < 810 ? 176 : citron.height < 1000 ? 238 : 286, citron.width * 0.40)
                height: width
                mode: citron.orbMode
                inputLevel: citron.soundLevel
                outputLevel: citron.outputLevel
                running: citron.visible && !citron.voiceMode
                scale: 0.90 + 0.10 * citron.shown
                Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.tap.duration; easing.type: Easing.OutBack } }
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
                         citron.phase === "downloading" ? "Getting Citron's voice ready… " + Math.round(citron.downloaded * 100) + "%" :
                         citron.phase === "connecting" ? "Connecting voice…" :
                         citron.micMuted ? "Microphone muted" : citron.phase === "speaking" ? "Speaking…" : "Listening…")
                        : citron.aiServiceBusy ? "Thinking…" : citron.toolTitle
                    color: Theme.vibrant.label
                    font { family: Theme.fontDisplay; pixelSize: Theme.font.title2.pixelSize; weight: Font.DemiBold }
                    layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.vibrant.shadow; shadowBlur: 0.9; shadowVerticalOffset: 2 }
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
                    color: citron.phase === "error" ? CitronColors.error : Theme.vibrant.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize }
                    layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.vibrant.shadow; shadowBlur: 0.9; shadowVerticalOffset: 2 }
                }
            }

            // The answer unfolds only when needed. The orb stays the visual
            // anchor instead of dropping an always-visible chat window.
            Item {
                id: resultArea
                width: parent.width
                height: citron.responseOpen ? Math.min(citron.height < 810 ? 164 : 235, Math.max(92, answerContent.implicitHeight + 28)) : 0
                opacity: citron.responseOpen ? 1 : 0
                visible: height > 1
                Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.tap.duration; easing.type: Easing.OutCubic } }
                Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.fade } }
                Shared.Glass {
                    anchors.fill: parent
                    role: "menu"; radius: Theme.radius.window
                    tint: CitronColors.answer
                    shadow: CitronColors.answerShadow
                }
                Flickable {
                    id: answerScroll
                    anchors { fill: parent; margins: 15 }
                    contentWidth: width
                    contentHeight: answerContent.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: answerContent
                        width: answerScroll.width
                        spacing: 9
                    Row {
                        width: parent.width
                        spacing: 10
                        Text {
                            width: parent.width - 86
                            color: Theme.vibrant.label
                            text: citron.aiServiceBusy ? "Working on it…" : "Response"
                            font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize; weight: Font.DemiBold }
                        }
                        Text {
                            text: citron.aiServiceBusy ? "Cancel" : "Copy"
                            visible: citron.aiServiceBusy || citron.answer.length > 0
                            Accessible.role: Accessible.Button
                            Accessible.name: text
                            Accessible.onPressAction: copyOrCancel()
                            color: CitronColors.link
                            font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
                            function copyOrCancel() {
                                if (citron.aiServiceBusy) {
                                    aiService.cancel()
                                    citron.responseNote = "Request cancelled."
                                } else Quickshell.clipboardText = citron.answer
                            }
                            MouseArea { anchors.fill: parent; onClicked: parent.copyOrCancel() }
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
                            color: Theme.vibrant.label
                            font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize }
                            lineHeight: 1.22
                        }
                    }
                    }
                }
            }

            // Writing Tools appear contextually, not as pages.
            Rectangle {
                id: contextArea
                width: parent.width
                height: citron.tool === "writing" ? (citron.height < 810 ? 77 : 94) : 0
                visible: height > 0
                radius: Theme.radius.panel
                color: CitronColors.field
                border { color: CitronColors.fieldBorder; width: 1 }
                TextEdit {
                    id: writingSource
                    visible: citron.tool === "writing"
                    anchors { fill: parent; margins: 14 }
                    color: Theme.vibrant.label; selectionColor: CitronColors.selection
                    wrapMode: TextEdit.Wrap
                    font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize }
                    clip: true
                    Text {
                        visible: !writingSource.text && writingSource.visible
                        text: "Paste the text you want to refine…"
                        color: Theme.vibrant.tertiaryLabel
                        font: writingSource.font
                    }
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
                    radius: height / 2
                    height: 30
                    width: labelText.implicitWidth + 24
                    color: citron.tool === kind ? CitronColors.chipOn : CitronColors.chip
                    border { color: citron.tool === kind ? CitronColors.chipOnBorder : CitronColors.chipBorder; width: 1 }
                    scale: tap.pressed && !Theme.reduceMotion ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.motion.hover; easing.type: Easing.OutBack } }
                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: chip.label
                        color: Theme.vibrant.label
                        font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize; weight: Font.Medium }
                    }
                    MouseArea { id: tap; anchors.fill: parent; onClicked: citron.chooseTool(chip.kind) }
                    Accessible.role: Accessible.Button
                    Accessible.name: label
                }
                ToolChip { label: citron.voiceMode ? "Type" : "Ask"; kind: "ask" }
                ToolChip { label: "Write"; kind: "writing" }
            }

            Item {
                id: capsule
                width: parent.width
                height: citron.height < 810 ? 52 : 58
                Shared.Glass {
                    anchors.fill: parent; role: "regular"; radius: height / 2
                    tint: CitronColors.composer; shadow: CitronColors.composerShadow
                }
                component SmallButton: Rectangle {
                    id: btn
                    property string symbol
                    property string description
                    property color shade: CitronColors.button
                    signal clicked()
                    width: 38; height: 38; radius: height / 2
                    color: shade
                    scale: mouse.pressed && !Theme.reduceMotion ? 0.93 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.motion.hover; easing.type: Easing.OutBack } }
                    Shared.Symbol { anchors.centerIn: parent; name: btn.symbol; size: 17; tone: "white" }
                    MouseArea { id: mouse; anchors.fill: parent; onClicked: btn.clicked() }
                    Accessible.role: Accessible.Button
                    Accessible.name: description
                }
                SmallButton {
                    id: micButton
                    anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    symbol: citron.voiceMode && citron.phase === "error" ? "arrow-clockwise" : "mic"
                    description: !citron.voiceMode ? "Start voice conversation"
                        : citron.phase === "error" ? "Retry voice connection" : citron.micMuted ? "Unmute" : "Mute"
                    shade: citron.voiceMode && !citron.micMuted ? CitronColors.live : CitronColors.button
                    onClicked: citron.toggleMic()
                }
                TextInput {
                    id: textEntry
                    objectName: "citronSystemPrompt"
                    anchors { left: micButton.right; leftMargin: 12; right: send.right; rightMargin: 46; verticalCenter: parent.verticalCenter }
                    height: 29
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.vibrant.label
                    selectionColor: CitronColors.selection
                    font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                    enabled: !citron.aiServiceBusy && !citron.voiceMode
                    focus: citron.open && !citron.voiceMode
                    onAccepted: citron.sendText()
                    Keys.onEscapePressed: citron.dismiss()
                    Text {
                        visible: !textEntry.text
                        text: citron.tool === "writing" ? "How should I rewrite it?" : "Ask anything…"
                        color: Theme.vibrant.tertiaryLabel
                        font: textEntry.font
                    }
                }
                SmallButton {
                    id: send
                    anchors { right: close.left; rightMargin: 7; verticalCenter: parent.verticalCenter }
                    symbol: "arrow-up"; description: "Send request"
                    shade: textEntry.text.trim() ? CitronColors.send : CitronColors.button
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
                text: "⌘⇧Space to talk · Esc to dismiss"
                color: Theme.vibrant.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.font.subheadline.pixelSize }
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.vibrant.shadow; shadowBlur: 0.9; shadowVerticalOffset: 2 }
            }
        }
    }
}
