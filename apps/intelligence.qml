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
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
        }
        toolbarRight: [
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
                        Rectangle {
                            width: 28; height: 28; radius: 9
                            color: Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: "C"
                                color: "#fff"
                                font { family: Theme.fontDisplay; pixelSize: 15; weight: Font.Bold }
                            }
                        }
                        Text {
                            text: "Citron"
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
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
                    font { family: Theme.fontUi; pixelSize: 11 }
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
                edit: "Edit an image with prompt-based refinements while preserving your original.")
            [page] ?? "Create and refine content quickly."

            function switchPage(p) {
                page = p
                message = ""
                service.error = ""
                showingOriginal = false
            }

            function send() {
                message = ""
                requestPrompt = prompt.text
                requestTask = page
                requestPhoto = photoPath
                if (page === "writing") output.text = ""
                const req = { task: page, prompt: prompt.text }
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
                        app.history = app.history.concat([{ role: "user", text: app.requestPrompt }, { role: "model", text: reply.text }]).slice(-40)
                        conversation.text = app.history.map(t => (t.role === "user" ? "You" : "Citron Intelligence") + "\n" + t.text).join("\n\n")
                        prompt.text = ""
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
                visible: app.page !== "settings"
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

                    Rectangle {
                        width: parent.width
                        height: 166
                        radius: 24
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#3d5ce6" }
                            GradientStop { position: 0.45; color: "#6047d8" }
                            GradientStop { position: 1; color: "#7a3ec7" }
                        }
                        border { width: 1; color: "#9c7bff" }

                        Row {
                            anchors { fill: parent; margins: 24 }
                            spacing: 18
                            Column {
                                width: parent.width * 0.64
                                spacing: 8
                                Text {
                                    width: parent.width
                                    text: app.heading
                                    wrapMode: Text.WordWrap
                                    color: "#fff"
                                    font { family: Theme.fontDisplay; pixelSize: 32; weight: Font.Bold }
                                }
                                Text {
                                    width: parent.width
                                    text: app.description
                                    wrapMode: Text.WordWrap
                                    color: "#eef2ff"
                                    font { family: Theme.fontUi; pixelSize: 13 }
                                }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: [
                                            { name: "Ask", page: "ask" },
                                            { name: "Write", page: "writing" },
                                            { name: "Image", page: "image" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 100
                                            height: 28
                                            radius: 14
                                            color: app.page === modelData.page ? "#ffffff26" : "#ffffff14"
                                            border { width: 1; color: "#ffffff36" }
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.name
                                                color: "#fff"
                                                font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                                            }
                                            TapHandler { onTapped: app.switchPage(modelData.page) }
                                        }
                                    }
                                }
                            }
                            Column {
                                width: parent.width * 0.36
                                spacing: 10
                                Rectangle {
                                    width: parent.width
                                    height: 92
                                    radius: 18
                                    color: "#ffffff12"
                                    border { width: 1; color: "#ffffff24" }
                                    Column {
                                        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                                        spacing: 6
                                        Text {
                                            text: "Context"
                                            color: "#dfe5ff"
                                            font { family: Theme.fontUi; pixelSize: 10; weight: Font.Bold; letterSpacing: 1.2 }
                                        }
                                        Text {
                                            text: app.page === "ask" ? "Questions & analysis" : app.page === "writing" ? "Editing & polishing" : app.page === "image" ? "Image generation" : "Photo refinement"
                                            color: "#fff"
                                            font { family: Theme.fontUi; pixelSize: 16; weight: Font.DemiBold }
                                        }
                                    }
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 44
                                    radius: 14
                                    color: "#ffffff12"
                                    border { width: 1; color: "#ffffff24" }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 10
                                        Symbol { name: "sparkles"; size: 16; tone: "white" }
                                        Text {
                                            text: "Gemini ready"
                                            color: Theme.label
                                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 12
                        visible: app.page === "ask" || app.page === "edit"
                        Button { text: app.photoPath ? "Change Photo…" : "Choose Photo…"; enabled: !service.busy; onClicked: photoDialog.open() }
                        Button { text: "Remove"; visible: !!app.photoPath; enabled: !service.busy; onClicked: app.photoPath = "" }
                        Button { text: "New Conversation"; visible: app.page === "ask"; enabled: !service.busy; onClicked: { app.history = []; conversation.text = ""; app.photoPath = ""; app.message = "" } }
                    }

                    Text {
                        visible: !!app.photoPath && (app.page === "ask" || app.page === "edit")
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: app.photoPath
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
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
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        visible: app.page === "writing" || app.page === "image" || app.page === "edit"
                        height: app.page === "writing" ? 52 : 56
                        AI.EditorBox {
                            id: prompt
                            width: parent.width - sendButton.width - 14
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
                        height: app.page === "ask" ? 280 : app.page === "writing" ? 260 : 320
                        radius: 22
                        color: Theme.dark ? "#13171d" : "#f5f5f8"
                        border { width: 1; color: Theme.separator }
                        visible: app.page === "ask" || app.page === "writing" || app.page === "image" || app.page === "edit"

                        Column {
                            anchors { fill: parent; margins: 14 }
                            spacing: 8

                            Row {
                                width: parent.width
                                visible: app.page === "ask"
                                Text {
                                    text: "Conversation"
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                                }
                                Item { width: 10; height: 1 }
                                Text {
                                    text: app.history.length ? (app.history.length + " exchanges") : "No messages yet"
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: 11 }
                                }
                            }

                            AI.EditorBox {
                                id: conversation
                                width: parent.width
                                height: app.page === "ask" ? parent.height - 20 : 0
                                visible: app.page === "ask"
                                readOnly: true
                                placeholder: "Your conversation appears here. Ctrl+Enter sends a request."
                            }

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
                                    font { family: Theme.fontUi; pixelSize: 14 }
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
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
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
