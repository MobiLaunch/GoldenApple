//@ pragma AppId org.goldengate.Intelligence
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import "lib"
import "lib/theme"
import "lib/paths.js" as Paths
import "lib/intelligence" as AI

ShellRoot {
    AppWindow {
        id: win
        title: "Citron Intelligence"
        implicitWidth: 1040
        implicitHeight: Math.min(820, (Quickshell.screens[0]?.height ?? 900) - 90)
        minimumSize: Qt.size(760, 620)
        sidebarWidth: 214
        background: Theme.contentBg
        toolbarCenter: Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Citron Intelligence"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.DemiBold }
        }
        toolbarRight: [
            ToolbarButton { symbol: "compose"; round: true; visible: app.page === "ask"; enabled: !service.busy && (app.history.length > 0 || !!app.photoPath); onClicked: app.newConversation() },
            ToolbarButton { symbol: "mic"; round: true; onClicked: voiceLaunch.startDetached() },
            ToolbarButton { symbol: "gear"; round: true; enabled: !service.busy; onClicked: app.page = "settings" }
        ]

        sidebar: [
            Column {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 16
                    color: Theme.dark ? "#171a1f" : "#f4f4f7"
                    border { width: 1; color: Theme.separator }
                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        CitronOrb {
                            width: 30; height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            mode: service.busy ? "thinking" : "idle"
                        }
                        Text {
                            text: "Citron"
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.DemiBold }
                        }
                    }
                }

                SidebarSection { text: "INTELLIGENCE" }
                Repeater {
                    model: [
                        ["ask", "Ask Anything", "bubble"],
                        ["writing", "Writing Tools", "textformat"],
                        ["image", "Create Image", "wand"],
                        ["edit", "Edit Photo", "photo"]
                    ]
                    delegate: SidebarRow {
                        required property var modelData
                        width: parent.width
                        text: modelData[1]
                        symbol: modelData[2]
                        selected: app.page === modelData[0]
                        enabled: !service.busy
                        onClicked: app.switchPage(modelData[0])
                    }
                }

                SidebarRow {
                    width: parent.width
                    text: "Talk to Citron"
                    symbol: "mic"
                    onClicked: voiceLaunch.startDetached()
                }

                SidebarSection { text: "PREFERENCES"; topSpacing: 22 }
                SidebarRow {
                    width: parent.width
                    text: "Settings"
                    symbol: "gear"
                    selected: app.page === "settings"
                    enabled: !service.busy
                    onClicked: app.page = "settings"
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.separator
                    opacity: 0.7
                }

                Text {
                    x: 6
                    width: parent.width - 12
                    text: "Powered by Google Gemini"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            }
        ]

        Process { id: voiceLaunch; command: ["gg-intelligence", "--voice"] }

        Item {
            id: app
            anchors.fill: parent
            property string page: Quickshell.env("GG_INTELLIGENCE_MODE") || "ask"
            property string photoPath: Quickshell.env("GG_INTELLIGENCE_PHOTO") || ""
            property var history: []
            property var images: []
            property string requestPrompt: ""
            property string requestTask: ""
            property string requestPhoto: ""
            property string resultTask: ""
            property string resultPhoto: ""
            property int imageIndex: 0
            property string message: ""
            property bool showingOriginal: false
            readonly property var modes: ["proofread", "rewrite", "friendly", "professional", "concise", "summary", "keypoints", "table", "custom"]
            readonly property bool imageTask: page === "image" || page === "edit"
            readonly property bool hasImageResult: images.length > 0 && page === resultTask && (page !== "edit" || photoPath === resultPhoto)
            readonly property string selectedImage: hasImageResult ? images[imageIndex] || images[0] : ""
            readonly property string heading: ({
                ask: "A little help. A lot of possibilities.",
                writing: "Make every word yours.",
                image: "Picture something new.",
                edit: "A fresh take on your photo."
            })[page] ?? "Any idea, instantly."
            readonly property string description: ({
                ask: "Ask a question, explore an idea, or attach an image to understand it.",
                writing: "Proofread, rewrite, summarize, or polish your own text with a single pass.",
                image: "Generate a new image from a prompt, then save the result in a click.",
                edit: "Edit an image with prompt-based refinements while preserving your original."
            })[page] ?? "Create and refine content quickly."

            function newConversation() {
                history = []
                photoPath = ""
                message = ""
                service.error = ""
                composer.text = ""
            }
            function ask(text) {
                composer.text = text
                send()
            }

            function switchPage(p) {
                page = p
                message = ""
                service.error = ""
                showingOriginal = false
            }

            function send() {
                message = ""
                requestPrompt = page === "ask" ? composer.text.trim() : prompt.text
                requestTask = page
                requestPhoto = photoPath
                if (page === "writing") output.text = ""
                const req = { task: page, prompt: requestPrompt }
                if (page === "ask") {
                    req.history = history.slice(-20)
                    if (photoPath) req.imagePath = photoPath
                }
                if (page === "writing") { req.text = source.text; req.mode = modes[writingMode.current] }
                if (page === "edit") req.imagePath = photoPath
                service.send(req)
            }

            AI.Service {
                id: service
                onCompleted: (action, reply) => {
                    if (!reply.ok) return
                    if (action === "export") { app.message = "Saved a copy to " + reply.savedPath; return }
                    if (action !== "generate") return
                    if (app.requestTask === "ask") {
                        app.history = app.history.concat([{ role: "user", text: app.requestPrompt, image: app.requestPhoto },
                                                          { role: "model", text: reply.text }]).slice(-40)
                        composer.text = ""
                        app.photoPath = ""
                    } else if (app.requestTask === "writing") output.text = reply.text
                    else {
                        if (app.images.length) cleanup.send({ action: "discard", images: app.images })
                        app.images = reply.images
                        app.imageIndex = 0
                        app.resultTask = app.requestTask
                        app.resultPhoto = app.requestPhoto
                        app.showingOriginal = false
                        app.message = reply.text || "Your image is ready. Save a copy to keep it."
                    }
                    if (reply.truncated) app.message = "The answer was cut short. Ask for a shorter response or use a smaller selection."
                }
            }

            AI.Service { id: cleanup }

            Flickable {
                visible: app.page === "settings"
                anchors { fill: parent; margins: 28 }
                contentWidth: width
                contentHeight: settingsLoader.height + 30
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Loader {
                    id: settingsLoader
                    width: parent.width
                    height: status === Loader.Ready && item ? item.implicitHeight : 0
                    active: app.page === "settings"
                    source: Qt.resolvedUrl("lib/intelligence/SettingsPanel.qml")
                    onLoaded: { if (item) item.menuParent = win.overlay }
                    property string details: ""
                    onStatusChanged: {
                        if (status === Loader.Error) {
                            const component = Qt.createComponent(
                                Qt.resolvedUrl("lib/intelligence/SettingsPanel.qml"),
                                Component.PreferSynchronous)
                            details = component.status === Component.Error
                                ? component.errorString() : "Settings panel could not initialize."
                            console.error("Citron Intelligence settings:", details)
                        } else if (status === Loader.Ready) {
                            details = ""
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: 12
                    visible: settingsLoader.status === Loader.Error
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Intelligence preferences couldn't load: " + settingsLoader.details
                        color: Theme.secondaryLabel
                    }
                    Button {
                        text: "Retry"
                        onClicked: {
                            settingsLoader.active = false
                            settingsLoader.active = true
                        }
                    }
                }
            }

            Flickable {
                visible: app.page !== "settings" && app.page !== "ask"
                anchors.fill: parent
                contentWidth: width
                contentHeight: workColumn.height + 36
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: workColumn
                    x: 26
                    y: 22
                    width: parent.width - 52
                    spacing: 18

                    Row {
                        width: parent.width
                        spacing: 16
                        CitronOrb {
                            width: 58; height: 58
                            anchors.verticalCenter: parent.verticalCenter
                            mode: service.busy ? "thinking" : "idle"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 74
                            spacing: 4
                            Text {
                                width: parent.width
                                text: app.heading
                                wrapMode: Text.WordWrap
                                color: Theme.label
                                font { family: Theme.fontDisplay; pixelSize: 26; weight: Font.Bold }
                            }
                            Text {
                                width: parent.width
                                text: app.description
                                wrapMode: Text.WordWrap
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 12
                        visible: app.page === "edit"
                        Button { text: app.photoPath ? "Change Photo…" : "Choose Photo…"; enabled: !service.busy; onClicked: photoDialog.open() }
                        Button { text: "Remove"; visible: !!app.photoPath; enabled: !service.busy; onClicked: app.photoPath = "" }
                    }

                    Text {
                        visible: !!app.photoPath && app.page === "edit"
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: app.photoPath
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }

                    Rectangle {
                        visible: app.page === "writing"
                        width: parent.width
                        height: 58
                        radius: 16
                        color: Theme.dark ? "#15181d" : "#eef1f5"
                        border { width: 1; color: Theme.separator }
                        Row {
                            anchors { fill: parent; margins: 12 }
                            spacing: 10
                            PopUpButton {
                                id: writingMode
                                width: 220
                                menuParent: win.overlay
                                enabled: !service.busy
                                options: ["Proofread", "Rewrite", "Friendly", "Professional", "Concise", "Summary", "Key Points", "Table", "Describe Your Change"]
                            }
                            Button { text: "Paste Text"; enabled: !service.busy; onClicked: source.text = Quickshell.clipboardText }
                            Button {
                                text: service.busy ? "Working…" : "Send"
                                prominent: true
                                enabled: sendButton.enabled
                                onClicked: app.send()
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        // Writing sends from its toolbar; this row is its custom instruction.
                        visible: app.page === "image" || app.page === "edit" || (app.page === "writing" && writingMode.current === 8)
                        height: app.page === "writing" ? 52 : 86
                        AI.EditorBox {
                            id: prompt
                            width: app.page === "writing" ? parent.width : parent.width - sendButton.width - 14
                            height: app.page === "writing" ? 50 : 86
                            visible: app.page !== "writing" || writingMode.current === 8
                            placeholder: app.page === "edit" ? "For example: remove the person in the background" : app.page === "image" ? "Describe your image…" : app.page === "writing" ? "Describe your change…" : "Ask anything…"
                            readOnly: service.busy
                            editor.Keys.onPressed: (event) => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Return && sendButton.enabled) {
                                    app.send();
                                    event.accepted = true;
                                }
                            }
                        }
                        Button {
                            id: sendButton
                            visible: app.page !== "writing"
                            width: 130
                            text: service.busy ? "Working…" : app.imageTask ? "Generate" : "Send"
                            prominent: true
                            enabled: !service.busy && (
                                app.page === "writing"
                                    ? source.text.trim().length > 0 && (writingMode.current !== 8 || prompt.text.trim().length > 0)
                                    : prompt.text.trim().length > 0
                            )
                            onClicked: app.send()
                        }
                    }

                    AI.EditorBox {
                        id: source
                        width: parent.width
                        height: Math.max(120, app.height * 0.18)
                        visible: app.page === "writing"
                        placeholder: "Paste or type the text to work with"
                        readOnly: service.busy
                    }

                    Rectangle {
                        width: parent.width
                        height: app.page === "writing" ? 260 : 320
                        radius: 22
                        color: Theme.dark ? "#13171d" : "#f5f5f8"
                        border { width: 1; color: Theme.separator }
                        visible: app.page === "writing" || app.page === "image" || app.page === "edit"

                        Column {
                            anchors { fill: parent; margins: 14 }
                            spacing: 8

                            AI.EditorBox {
                                id: output
                                width: parent.width
                                height: app.page === "writing" ? parent.height - 20 : 0
                                visible: app.page === "writing"
                                readOnly: true
                                placeholder: "Your result appears here"
                            }

                            Rectangle {
                                visible: app.page === "image" || app.page === "edit"
                                width: parent.width
                                height: parent.height - 10
                                radius: 18
                                color: Theme.dark ? "#181c22" : "#eef1f5"
                                border { width: 1; color: Theme.separator }
                                Image {
                                    anchors { fill: parent; margins: 10 }
                                    source: app.showingOriginal || !app.hasImageResult ? (app.page === "edit" && app.photoPath ? Paths.fileUrl(app.photoPath) : "") : Paths.fileUrl(app.selectedImage)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    autoTransform: true
                                    sourceSize: Qt.size(width * 2, height * 2)
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !app.hasImageResult && !(app.page === "edit" && app.photoPath)
                                    text: "Your image will appear here"
                                    color: Theme.tertiaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                                }
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: app.page === "writing" || app.page === "image" || app.page === "edit"
                        Button {
                            text: "Cancel"
                            visible: service.busy
                            onClicked: service.cancel()
                        }
                        Button {
                            text: "Copy Result"
                            visible: app.page === "writing"
                            enabled: !!output.text
                            onClicked: Quickshell.clipboardText = output.text
                        }
                        Button {
                            text: "Save Copy…"
                            visible: app.imageTask
                            enabled: app.hasImageResult && !service.busy
                            onClicked: {
                                saveDialog.defaultSuffix = app.selectedImage.split(".").pop().toLowerCase()
                                saveDialog.open()
                            }
                        }
                        Button {
                            text: app.showingOriginal ? "Show Result" : "Show Original"
                            visible: app.page === "edit" && app.hasImageResult
                            onClicked: app.showingOriginal = !app.showingOriginal
                        }
                        PopUpButton {
                            visible: app.hasImageResult && app.images.length > 1
                            menuParent: win.overlay
                            options: app.images.map((_, i) => "Image " + (i + 1))
                            current: app.imageIndex
                            onPicked: (i) => app.imageIndex = i
                        }
                    }

                    Text {
                        width: parent.width
                        height: 42
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        text: service.error || app.message || "Requests are sent to Google Gemini. Review generated content before using it."
                        color: service.error ? "#ff453a" : Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                }
            }

            // Ask Anything: a conversation, with a composer at the bottom.
            Item {
                id: chat
                anchors.fill: parent
                visible: app.page === "ask"

                ListView {
                    id: messages
                    objectName: "citronChat"
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: composerBar.top; margins: 26; bottomMargin: 12 }
                    clip: true
                    spacing: 12
                    model: app.history
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: Qt.callLater(() => messages.positionViewAtEnd())
                    footer: Item {
                        width: messages.width
                        height: service.busy ? 58 : 0
                        // Citron thinking: your question, then the orb at work.
                        Row {
                            visible: service.busy
                            y: 12
                            spacing: 10
                            CitronOrb { width: 34; height: 34; mode: "thinking" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Thinking…"
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                            }
                        }
                    }
                    delegate: Item {
                        id: turn
                        required property var modelData
                        readonly property bool mine: modelData.role === "user"
                        width: messages.width
                        height: bubble.height + (turn.mine && modelData.image ? 0 : 0)
                        Rectangle {
                            id: bubble
                            anchors { right: turn.mine ? parent.right : undefined; left: turn.mine ? undefined : parent.left }
                            width: Math.min(messages.width * (turn.mine ? 0.7 : 0.86), body.implicitWidth + 28)
                            height: body.implicitHeight + 20
                            radius: 18
                            color: turn.mine ? Theme.accent : (Theme.dark ? "#2a2b30" : "#efeff3")
                            TextArea {
                                id: body
                                writingToolsEnabled: false
                                x: 14; y: 10
                                width: Math.min(messages.width * (turn.mine ? 0.7 : 0.86) - 28, implicitWidth)
                                text: turn.modelData.text + (turn.modelData.image ? "\n📎 " + turn.modelData.image.split("/").pop() : "")
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                color: turn.mine ? "#ffffff" : Theme.label
                                selectionColor: turn.mine ? "#66ffffff" : Theme.accent
                                font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                            }
                        }
                    }
                }
                Scroller { flickable: messages }

                // Nothing asked yet: the orb, a welcome, and a few ideas.
                Column {
                    visible: !app.history.length && !service.busy
                    anchors { centerIn: messages; verticalCenterOffset: -20 }
                    width: Math.min(660, messages.width)
                    spacing: 12
                    CitronOrb { anchors.horizontalCenter: parent.horizontalCenter; width: 112; height: 112; mode: "idle" }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "A little help. A lot of possibilities."
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: Theme.fs(24); weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Ask a question, explore an idea, or attach a photo to understand it."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                    Flow {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, ideas.contentWidth)
                        spacing: 8
                        topPadding: 6
                        // The chips' total width, to centre them when they fit on a line.
                        QtObject { id: ideas; property real contentWidth: 640 }
                        Repeater {
                            model: ["Explain something simply", "Plan my week", "Help me write an email", "Ideas for dinner tonight"]
                            delegate: Rectangle {
                                required property string modelData
                                width: idea.implicitWidth + 26; height: 32; radius: 16
                                color: ideaTap.containsMouse ? (Theme.dark ? "#33ffffff" : "#14000000") : (Theme.dark ? "#1fffffff" : "#0a000000")
                                border { width: 1; color: Theme.separator }
                                Text { id: idea; anchors.centerIn: parent; text: parent.modelData; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                                MouseArea { id: ideaTap; anchors.fill: parent; hoverEnabled: true; enabled: !service.busy; onClicked: app.ask(parent.modelData) }
                            }
                        }
                    }
                }

                // The composer: attach a photo, type, send. Return sends;
                // Shift+Return starts a new line.
                Rectangle {
                    id: composerBar
                    anchors { left: parent.left; right: parent.right; bottom: chatStatus.top; leftMargin: 26; rightMargin: 26; bottomMargin: 6 }
                    height: Math.min(150, Math.max(48, composer.contentHeight + 26)) + (app.photoPath ? 30 : 0)
                    radius: 24
                    color: Theme.dark ? "#1c1d21" : "#ffffff"
                    border { width: 1; color: composer.activeFocus ? Theme.accent : Theme.separator }
                    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    // The attached photo, as a chip with a remove button.
                    Rectangle {
                        visible: !!app.photoPath
                        x: 48; y: 8
                        width: Math.min(parent.width - 100, chipText.implicitWidth + 40); height: 24; radius: 12
                        color: Theme.dark ? "#2c2d33" : "#eef0f4"
                        Text {
                            id: chipText
                            anchors { left: parent.left; leftMargin: 10; right: chipX.left; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideMiddle
                            text: "📎 " + app.photoPath.split("/").pop()
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                        Symbol { id: chipX; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } name: "xmark"; size: 10
                            MouseArea { anchors { fill: parent; margins: -6 } onClicked: app.photoPath = "" } }
                    }
                    Rectangle {
                        id: attach
                        anchors { left: parent.left; leftMargin: 8; bottom: parent.bottom; bottomMargin: 8 }
                        width: 32; height: 32; radius: 16
                        color: attachTap.containsMouse ? (Theme.dark ? "#2cffffff" : "#10000000") : "transparent"
                        Symbol { anchors.centerIn: parent; name: "photo"; size: 16 }
                        MouseArea { id: attachTap; anchors.fill: parent; hoverEnabled: true; enabled: !service.busy; onClicked: photoDialog.open() }
                        Accessible.name: "Attach a photo"
                    }
                    Flickable {
                        id: composerScroll
                        anchors { left: attach.right; right: sendRound.left; bottom: parent.bottom; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: app.photoPath ? 40 : 13; bottomMargin: 13 }
                        contentWidth: width
                        contentHeight: composer.contentHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        TextArea {
                            id: composer
                            objectName: "citronComposer"
                            width: composerScroll.width
                            textFormat: TextEdit.PlainText
                            writingToolsEnabled: false
                            placeholder: "Ask Citron anything"
                            readOnly: service.busy
                            Keys.onReturnPressed: (event) => {
                                if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                                if (sendRound.ready) app.send()
                            }
                            Keys.onEnterPressed: (event) => { if (sendRound.ready) app.send() }
                        }
                    }
                    Rectangle {
                        id: sendRound
                        readonly property bool ready: !service.busy && composer.text.trim().length > 0
                        anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 8 }
                        width: 32; height: 32; radius: 16
                        color: ready ? Theme.accent : (Theme.dark ? "#3a3b40" : "#d9dadf")
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Symbol { anchors.centerIn: parent; name: service.busy ? "stop" : "arrow-up"; size: 15; tone: "white" }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: service.busy ? service.cancel() : (sendRound.ready ? app.send() : null)
                        }
                        Accessible.name: service.busy ? "Stop" : "Send"
                    }
                }
                Text {
                    id: chatStatus
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 30; rightMargin: 30; bottomMargin: 12 }
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: service.error || app.message || "Citron uses Google Gemini. Check important information."
                    color: service.error ? "#ff453a" : Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            }

            FileDialog {
                id: photoDialog
                title: "Choose a Photo"
                fileMode: FileDialog.OpenFile
                nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
                onAccepted: app.photoPath = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
            }

            FileDialog {
                id: saveDialog
                title: "Save a Copy"
                fileMode: FileDialog.SaveFile
                onAccepted: service.send({ action: "export", source: app.selectedImage, destination: decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")) })
            }
        }
    }
}
