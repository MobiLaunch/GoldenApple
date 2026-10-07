//@ pragma AppId org.goldengate.TextEdit
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Dialogs
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        objectName: "textEditWindow"
        title: editor.fileName
        implicitWidth: 860
        implicitHeight: 650
        minimumSize: Qt.size(560, 380)
        background: Theme.contentBg
        closeAction: () => editor.requestAction(() => Qt.quit())

        toolbarLeft: [
            ToolbarButton { round: true; symbol: "doc"; enabled: !editor.loading && !editor.saving; onClicked: editor.requestAction(() => editor.newDocument()) },
            ToolbarButton { round: true; symbol: "folder"; enabled: !editor.loading && !editor.saving; onClicked: editor.requestAction(() => openDialog.open()) },
            ToolbarButton { round: true; symbol: "wand"; enabled: body.length > 0 && !editor.loading; onClicked: body.openWritingTools() }
        ]
        toolbarRight: [
            Text {
                visible: editor.dirty
                anchors.verticalCenter: parent.verticalCenter
                text: "Edited"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
            },
            ToolbarButton {
                round: true
                symbol: "download"
                enabled: editor.dirty && !editor.saving && !editor.loading
                onClicked: editor.save()
            }
        ]

        toolbarCenter: Text {
            anchors.verticalCenter: parent.verticalCenter
            text: editor.fileName
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
        }

        FileDialog {
            id: openDialog; title: "Open Document"; fileMode: FileDialog.OpenFile
            onAccepted: editor.openPath(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
        }
        FileDialog {
            id: saveDialog; title: "Save Document"; fileMode: FileDialog.SaveFile; defaultSuffix: "txt"
            onAccepted: editor.saveTo(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
        }

        Item {
            id: editor
            objectName: "textDocument"
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("textedit/helper.py").toString().replace("file://", "")
            property string path: Quickshell.env("GG_TEXTEDIT_FILE") || ""
            property bool dirty: false
            property bool loading: false
            property bool saving: false
            property string error: ""
            property string savedText: ""   // what is on disk; "baseline" is a final Item property in Qt 6.11
            property string pendingText: ""
            property string pendingPath: ""
            property var pendingAction: null
            readonly property string fileName: path ? path.split("/").pop() : "Untitled"

            function requestAction(action) {
                if (saving || loading) return
                if (dirty) { pendingAction = action; discard.visible = true }
                else action()
            }

            function newDocument() {
                path = ""
                body.text = ""
                savedText = ""
                dirty = false
                error = ""
            }

            function openPath(p) {
                if (!p || loading || saving)
                    return
                pendingPath = p
                loading = true
                error = ""
                readProc.command = ["python3", helper, "read", p]
                readProc.running = true
            }

            function save() {
                if (saving || loading) return
                if (!path) { saveDialog.open(); return }
                saveTo(path)
            }
            function saveTo(p) {
                if (!p || saving || loading) return
                pendingPath = p
                pendingText = body.text
                saving = true
                error = ""
                writeProc.command = ["python3", helper, "write", p]
                writeProc.running = true
            }

            Component.onCompleted: {
                if (path)
                    openPath(path)
            }

            Process {
                id: readProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                editor.path = editor.pendingPath
                                body.text = r.text ?? ""
                                editor.savedText = body.text
                                editor.dirty = false
                            } else {
                                editor.error = r.error ?? "The file could not be opened."
                            }
                        } catch (e) {
                            editor.error = "The file could not be opened."
                        }
                    }
                }
                onExited: editor.loading = false
            }

            Process {
                id: writeProc
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                editor.path = editor.pendingPath
                                editor.savedText = editor.pendingText
                                editor.dirty = body.text !== editor.savedText
                            } else {
                                editor.error = r.error ?? "The document could not be saved."
                            }
                        } catch (e) {
                            editor.error = "The document could not be saved."
                        }
                    }
                }
                onStarted: {
                    write(editor.pendingText)
                    stdinEnabled = false
                }
                onExited: {
                    stdinEnabled = true
                    editor.saving = false
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.dark ? "#19191b" : "#ffffff"
            }

            Flickable {
                id: page
                anchors { fill: parent; margins: 0 }
                contentWidth: width
                contentHeight: Math.max(height, body.contentHeight + 96)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextArea {
                    id: body
                    objectName: "textEditBody"
                    textFormat: TextEdit.PlainText
                    writingContext: editor.path
                    readOnly: editor.loading
                    x: Math.max(52, (page.width - width) / 2)
                    y: 42
                    width: Math.min(720, page.width - 104)
                    height: Math.max(page.height - 84, contentHeight)
                    color: Theme.label
                    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
                    selectedTextColor: Theme.label
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    activeFocusOnTab: true
                    persistentSelection: true
                    font { family: Theme.fontUi; pixelSize: Theme.fs(15) }
                    onTextChanged: {
                        if (!editor.loading)
                            editor.dirty = text !== editor.savedText
                    }
                    Keys.onPressed: (event) => {
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                            editor.save()
                            event.accepted = true
                        }
                    }
                }
            }

            Glass {
                visible: !!editor.error
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                width: Math.min(520, parent.width - 40)
                height: 50
                radius: 16
                tint: Theme.dark ? "#d02b1f24" : "#eefdf0f0"
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: editor.error
                    color: "#ff453a"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
            }
        }
        Rectangle {
            id: discard
            objectName: "unsavedChanges"
            parent: win.overlay
            visible: false
            anchors.fill: parent; color: "#66000000"; z: 100
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors.centerIn: parent; width: Math.min(460, parent.width - 32); height: 170
                radius: 20; color: Theme.contentBg
                Column {
                    anchors { fill: parent; margins: 24 }
                    spacing: 16
                    Text { text: "Keep your changes?"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.Bold } }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "This document has unsaved changes. Save it before continuing, or discard the changes."; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                    Row {
                        spacing: 8
                        Button { text: "Cancel"; onClicked: { discard.visible = false; editor.pendingAction = null } }
                        Button { text: "Discard"; destructive: true; onClicked: { const action = editor.pendingAction; discard.visible = false; editor.pendingAction = null; if (action) action() } }
                        Button { text: "Save…"; prominent: true; onClicked: { discard.visible = false; editor.pendingAction = null; editor.save() } }
                    }
                }
            }
        }
    }
}
