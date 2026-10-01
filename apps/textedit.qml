//@ pragma AppId org.goldengate.TextEdit
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: editor.fileName
        implicitWidth: 860
        implicitHeight: 650
        minimumSize: Qt.size(560, 380)
        background: Theme.contentBg

        toolbarLeft: [
            ToolbarButton { round: true; symbol: "doc"; onClicked: editor.newDocument() },
            ToolbarButton { round: true; symbol: "folder"; onClicked: { pathField.visible = true; pathField.input.forceActiveFocus() } }
        ]
        toolbarRight: [
            Text {
                visible: editor.dirty
                anchors.verticalCenter: parent.verticalCenter
                text: "Edited"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11 }
            },
            ToolbarButton {
                round: true
                symbol: "download"
                enabled: editor.path.length > 0 && editor.dirty && !editor.saving
                onClicked: editor.save()
            }
        ]

        toolbarCenter: Text {
            anchors.verticalCenter: parent.verticalCenter
            text: editor.fileName
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
        }

        toolbarItems: [
            TextField {
                id: pathField
                visible: false
                x: win.contentX + (parent.width - win.contentX - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(420, parent.width - 300)
                placeholder: "Path to a text file"
                text: editor.path
                onAccepted: {
                    editor.openPath(text)
                    visible = false
                }
                input.Keys.onEscapePressed: visible = false
            }
        ]

        Item {
            id: editor
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("textedit/helper.py").toString().replace("file://", "")
            property string path: Quickshell.env("GG_TEXTEDIT_FILE") || ""
            property bool dirty: false
            property bool loading: false
            property bool saving: false
            property string error: ""
            property string baseline: ""
            readonly property string fileName: path ? path.split("/").pop() : "Untitled"

            function newDocument() {
                path = ""
                body.text = ""
                baseline = ""
                dirty = false
                error = ""
                pathField.text = ""
            }

            function openPath(p) {
                if (!p)
                    return
                path = p
                pathField.text = p
                loading = true
                error = ""
                readProc.command = ["python3", helper, "read", p]
                readProc.running = true
            }

            function save() {
                if (!path || saving)
                    return
                saving = true
                error = ""
                writeProc.command = ["python3", helper, "write", path]
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
                                body.text = r.text ?? ""
                                editor.baseline = body.text
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
                                editor.baseline = body.text
                                editor.dirty = false
                            } else {
                                editor.error = r.error ?? "The document could not be saved."
                            }
                        } catch (e) {
                            editor.error = "The document could not be saved."
                        }
                    }
                }
                onStarted: {
                    write(body.text)
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

                TextEdit {
                    id: body
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
                    font { family: Theme.fontUi; pixelSize: 15 }
                    onTextChanged: {
                        if (!editor.loading)
                            editor.dirty = text !== editor.baseline
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
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
            }
        }
    }
}
