//@ pragma AppId org.goldengate.Intelligence
import Quickshell
import QtQuick
import QtQuick.Dialogs
import "lib"
import "lib/theme"
import "lib/paths.js" as Paths
import "lib/intelligence" as AI

ShellRoot {
    AppWindow {
        id: win
        title: "Citron Intelligence"
        implicitWidth: 960
        implicitHeight: Math.min(760, (Quickshell.screens[0]?.height ?? 900) - 90)
        minimumSize: Qt.size(720, 590)
        sidebarWidth: 184
        background: Theme.contentBg
        toolbarCenter: Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Citron Intelligence"; color: Theme.label
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
        }
        toolbarRight: [ToolbarButton { symbol: "gear"; round: true; enabled: !service.busy; onClicked: app.page = "settings" }]
        sidebar: [
            Column {
                width: parent.width; spacing: 6
                SidebarSection { text: "INTELLIGENCE" }
                Repeater {
                    model: [ ["ask", "Ask Anything", "bubble"], ["writing", "Writing Tools", "textformat"],
                             ["image", "Create Image", "wand"], ["edit", "Edit Photo", "photo"] ]
                    delegate: SidebarRow {
                        required property var modelData
                        width: parent.width; text: modelData[1]; symbol: modelData[2]
                        selected: app.page === modelData[0]; enabled: !service.busy
                        onClicked: app.switchPage(modelData[0])
                    }
                }
                SidebarSection { text: "PREFERENCES"; topSpacing: 22 }
                SidebarRow { width: parent.width; text: "Settings"; symbol: "gear"; selected: app.page === "settings"; enabled: !service.busy; onClicked: app.page = "settings" }
                Text {
                    x: 12; width: parent.width - 24; wrapMode: Text.Wrap
                    text: "Powered by Google Gemini"; color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
            }
        ]
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
            readonly property string heading: ({ask: "A little help. A lot of possibilities.", writing: "Make every word yours.", image: "Picture something new.", edit: "A fresh take on your photo."})[page] || "Citron Intelligence"
            readonly property string description: ({ask: "Ask a question, explore an idea, or attach an image to understand it.", writing: "Proofread, rewrite, summarize, or describe your own change.", image: "Describe a scene, an illustration, or an idea to bring to life.", edit: "Describe what to change. Your original photo stays untouched."})[page] || ""
            function switchPage(p) {
                page = p
                message = ""; service.error = ""; showingOriginal = false
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
                        app.history = app.history.concat([{role: "user", text: app.requestPrompt}, {role: "model", text: reply.text}]).slice(-40)
                        conversation.text = app.history.map(t => (t.role === "user" ? "You" : "Citron Intelligence") + "\n" + t.text).join("\n\n")
                        prompt.text = ""
                    } else if (app.requestTask === "writing") output.text = reply.text
                    else {
                        if (app.images.length) cleanup.send({action: "discard", images: app.images})
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
                contentWidth: width; contentHeight: settingsLoader.height + 30
                clip: true; boundsBehavior: Flickable.StopAtBounds
                Loader {
                    id: settingsLoader
                    width: parent.width
                    height: status === Loader.Ready && item ? item.implicitHeight : 0
                    active: app.page === "settings"
                    source: Qt.resolvedUrl("lib/intelligence/SettingsPanel.qml")
                    onLoaded: { if (item) item.menuParent = win.overlay }
                    onStatusChanged: {
                        if (status === Loader.Error)
                            console.warn("Citron Intelligence: settings panel could not load")
                    }
                }
                Column {
                    width: parent.width
                    spacing: 12
                    visible: settingsLoader.status === Loader.Error
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Intelligence preferences couldn't load. Check the Quickshell log, then retry."
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
                contentWidth: width; contentHeight: workColumn.height + 44
                clip: true; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: workColumn
                x: 26; y: 22; width: parent.width - 52; spacing: 12
                Text { width: parent.width; wrapMode: Text.Wrap; text: app.heading; color: Theme.label; font { family: Theme.fontUi; pixelSize: 25; weight: Font.Bold } }
                Text { width: parent.width; wrapMode: Text.Wrap; text: app.description; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } }
                Row {
                    spacing: 8
                    visible: app.page === "ask" || app.page === "edit"
                    Button { text: app.photoPath ? "Change Photo…" : "Choose Photo…"; enabled: !service.busy; onClicked: photoDialog.open() }
                    Button { text: "Remove"; visible: !!app.photoPath; enabled: !service.busy; onClicked: app.photoPath = "" }
                    Button {
                        text: "New Conversation"; visible: app.page === "ask"; enabled: !service.busy
                        onClicked: { app.history = []; conversation.text = ""; app.photoPath = ""; app.message = "" }
                    }
                }
                Text {
                    visible: !!app.photoPath && (app.page === "ask" || app.page === "edit")
                    width: parent.width; elide: Text.ElideMiddle
                    text: app.photoPath; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 }
                }
                Row {
                    visible: app.page === "writing"; spacing: 10
                    PopUpButton {
                        id: writingMode; width: 220; menuParent: win.overlay; enabled: !service.busy
                        options: ["Proofread", "Rewrite", "Friendly", "Professional", "Concise", "Summary", "Key Points", "Table", "Describe Your Change"]
                    }
                    Button { text: "Paste Text"; enabled: !service.busy; onClicked: source.text = Quickshell.clipboardText }
                }
                AI.EditorBox { id: source; visible: app.page === "writing"; width: parent.width; height: Math.max(80, app.height * 0.18); placeholder: "Paste or type the text to work with"; readOnly: service.busy }
                AI.EditorBox {
                    id: prompt; width: parent.width
                    height: app.page === "writing" ? 50 : 86
                    visible: app.page !== "writing" || writingMode.current === 8
                    placeholder: app.page === "edit" ? "For example: remove the person in the background" : app.page === "image" ? "Describe your image…" : app.page === "writing" ? "Describe your change…" : "Ask anything…"
                    readOnly: service.busy
                    editor.Keys.onPressed: (event) => {
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Return && sendButton.enabled) { app.send(); event.accepted = true }
                    }
                }
                Flow {
                    width: parent.width; spacing: 8
                    Button {
                        id: sendButton
                        text: service.busy ? "Working…" : app.imageTask ? "Generate" : "Send to Gemini"
                        prominent: true
                        enabled: !service.busy && (app.page === "writing" ? source.text.trim().length > 0 && (writingMode.current !== 8 || prompt.text.trim().length > 0) : prompt.text.trim().length > 0) && (app.page !== "edit" || !!app.photoPath)
                        onClicked: app.send()
                    }
                    Button { text: "Cancel"; visible: service.busy; onClicked: service.cancel() }
                    Button { text: "Copy Result"; visible: app.page === "writing"; enabled: !!output.text; onClicked: Quickshell.clipboardText = output.text }
                    Button { text: "Save Copy…"; visible: app.imageTask; enabled: app.hasImageResult && !service.busy; onClicked: { saveDialog.defaultSuffix = app.selectedImage.split(".").pop(); saveDialog.open() } }
                    Button { text: app.showingOriginal ? "Show Result" : "Show Original"; visible: app.page === "edit" && app.hasImageResult; onClicked: app.showingOriginal = !app.showingOriginal }
                    PopUpButton {
                        visible: app.hasImageResult && app.images.length > 1; menuParent: win.overlay
                        options: app.images.map((_, i) => "Image " + (i + 1)); current: app.imageIndex
                        onPicked: (i) => app.imageIndex = i
                    }
                }
                AI.EditorBox {
                    id: conversation; width: parent.width; height: Math.max(80, app.height - 360 - (app.photoPath ? 25 : 0))
                    visible: app.page === "ask"; readOnly: true; placeholder: "Your conversation appears here. Ctrl+Enter sends a request."
                }
                AI.EditorBox {
                    id: output; width: parent.width; height: Math.max(80, app.height - source.height - 265 - (prompt.visible ? 62 : 0))
                    visible: app.page === "writing"; readOnly: true; placeholder: "Your result appears here"
                }
                Rectangle {
                    width: parent.width; height: Math.max(90, app.height - (app.page === "edit" ? 385 : 320))
                    visible: app.imageTask; radius: 18; color: Theme.dark ? "#151518" : "#f0f0f5"
                    Image {
                        anchors { fill: parent; margins: 10 }
                        source: app.showingOriginal || !app.hasImageResult ? (app.page === "edit" && app.photoPath ? Paths.fileUrl(app.photoPath) : "") : Paths.fileUrl(app.selectedImage)
                        fillMode: Image.PreserveAspectFit; asynchronous: true; autoTransform: true
                        sourceSize: Qt.size(width * 2, height * 2)
                    }
                    Text {
                        anchors.centerIn: parent; visible: !app.hasImageResult && !(app.page === "edit" && app.photoPath)
                        text: "Your image will appear here"; color: Theme.tertiaryLabel; font { family: Theme.fontUi; pixelSize: 14 }
                    }
                }
                Text {
                    width: parent.width; height: 42; maximumLineCount: 3; elide: Text.ElideRight; wrapMode: Text.Wrap
                    text: service.error || app.message || "Requests are sent to Google Gemini. Review generated content before using it."
                    color: service.error ? "#ff453a" : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
            }
            }
            FileDialog {
                id: photoDialog; title: "Choose a Photo"; fileMode: FileDialog.OpenFile
                nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
                onAccepted: app.photoPath = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
            }
            FileDialog {
                id: saveDialog; title: "Save a Copy"; fileMode: FileDialog.SaveFile
                onAccepted: service.send({action: "export", source: app.selectedImage, destination: decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))})
            }
        }
    }
}
