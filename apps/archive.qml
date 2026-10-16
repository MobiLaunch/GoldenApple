//@ pragma AppId org.goldengate.ArchiveUtility
// Native CitronOS Archive Utility — files preview, inspect and safely extract.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Archive Utility"
        implicitWidth: Math.min(850, (Quickshell.screens[0]?.width ?? 1280) - 90)
        implicitHeight: Math.min(625, (Quickshell.screens[0]?.height ?? 900) - 135)
        minimumSize: Qt.size(620, 430)
        background: Theme.contentBg

        toolbarItems: [
            Row {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 8
                Button {
                    text: "Open Archive…"
                    enabled: !utility.busy
                    onClicked: archivePicker.open()
                }
                Button {
                    text: "Create ZIP…"
                    enabled: !utility.busy
                    onClicked: createPicker.open()
                }
            }
        ]

        Item {
            id: utility
            objectName: "archiveUtility"
            anchors.fill: parent
            property string sourcePath: Quickshell.env("GG_ARCHIVE_PATH") ?? ""
            property var entries: []
            property int totalCount: 0
            property real totalSize: 0
            property bool truncated: false
            property bool busy: worker.running
            property string operation: ""
            property string status: ""
            property string error: ""
            property real progress: 0
            property bool succeeded: false
            property string resultPath: ""
            readonly property string backend: decodeURIComponent(Qt.resolvedUrl("archive/helper.py").toString().replace("file://", ""))

            function fromUrl(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")) }
            function sizeText(bytes) {
                let n = Math.max(0, Number(bytes) || 0)
                const units = ["B", "KB", "MB", "GB", "TB"]
                let unit = 0
                while (n >= 1024 && unit < units.length - 1) { n /= 1024; unit++ }
                return (unit ? n.toFixed(n >= 10 ? 0 : 1) : Math.round(n)) + " " + units[unit]
            }
            function run(action, args) {
                if (worker.running) return
                error = ""
                status = ""
                succeeded = false
                resultPath = ""
                operation = action
                progress = 0
                worker.command = ["python3", backend, action].concat(args)
                worker.running = true
            }
            function inspect(path) {
                if (!path || busy) return
                sourcePath = path
                entries = []
                totalCount = 0
                totalSize = 0
                run("inspect", [path])
            }
            function extractTo(destination) {
                if (!sourcePath || busy) return
                run("extract", destination ? [sourcePath, destination] : [sourcePath])
            }
            function createPaths(paths) {
                if (!paths.length || busy) return
                run("create", paths)
            }
            function accept(line) {
                let result
                try { result = JSON.parse(line) } catch (e) { return }
                if (result.event === "progress") {
                    progress = result.total > 0 ? result.completed / result.total : 0
                    status = "Processing " + result.completed + (result.total ? " of " + result.total : "") + " items…"
                } else if (result.event === "done") {
                    if (!result.ok) { error = result.error ?? "The archive operation failed."; return }
                    succeeded = true
                    if (result.mode === "inspect") {
                        entries = result.entries ?? []
                        totalCount = result.count ?? 0
                        totalSize = result.totalSize ?? 0
                        truncated = !!result.truncated
                        status = totalCount + (totalCount === 1 ? " item" : " items") + " • " + sizeText(totalSize) + " uncompressed"
                    } else {
                        resultPath = result.destination ?? ""
                        status = result.mode === "create" ? "ZIP created successfully." : "Extraction complete."
                        if (result.mode === "create") sourcePath = resultPath
                    }
                }
            }

            Component.onCompleted: if (sourcePath) Qt.callLater(() => inspect(sourcePath))
            Shortcut { sequence: "Ctrl+O"; onActivated: if (!utility.busy) archivePicker.open() }
            Shortcut { sequence: "Ctrl+E"; onActivated: if (!utility.busy && utility.sourcePath) utility.extractTo("") }
            Process {
                id: worker
                stdout: SplitParser { onRead: (line) => utility.accept(line) }
                stderr: StdioCollector { id: workerErrors }
                onExited: (code) => {
                    if (code !== 0 && !utility.error)
                        utility.error = workerErrors.text.trim() || "The archive could not be processed."
                    if (code === 0 && utility.operation === "create" && utility.resultPath)
                        Qt.callLater(() => utility.inspect(utility.resultPath))
                }
            }

            FileDialog {
                id: archivePicker
                title: "Open Archive"
                nameFilters: ["Archives (*.zip *.cbz *.tar *.tar.gz *.tgz *.tar.xz *.txz *.tar.bz2 *.tbz *.tbz2)", "All files (*)"]
                onAccepted: utility.inspect(utility.fromUrl(selectedFile))
            }
            FileDialog {
                id: createPicker
                title: "Choose Files to Compress"
                fileMode: FileDialog.OpenFiles
                onAccepted: utility.createPaths(Array.from(selectedFiles).map((u) => utility.fromUrl(u)))
            }
            FolderDialog {
                id: destinationPicker
                title: "Choose Extraction Destination"
                onAccepted: utility.extractTo(utility.fromUrl(selectedFolder))
            }

            ColumnLayout {
                anchors { fill: parent; margins: 22 }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        width: 48; height: 48; radius: 15
                        color: Theme.dark ? "#243e57" : "#e8f2ff"
                        Symbol { anchors.centerIn: parent; name: "shippingbox"; size: 27; tone: "accent" }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            text: utility.sourcePath ? utility.sourcePath.split("/").pop() : "Archive Utility"
                            color: Theme.label
                            font { family: Theme.fontDisplay; pixelSize: Theme.fs(22); weight: Font.DemiBold }
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Text {
                            text: utility.sourcePath ? utility.sourcePath : "Open ZIP and TAR archives, or compress files into a ZIP."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 11
                    color: Theme.dark ? "#17212d" : "#eff3f9"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        Text {
                            Layout.fillWidth: true
                            text: utility.error ? utility.error : utility.busy
                                ? (utility.status || "Reading archive…")
                                : utility.status || "Archives are extracted into their own folder, never over existing files."
                            color: utility.error ? Theme.accentRed : Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                        }
                        Symbol { visible: utility.succeeded && !utility.error; name: "checkmark"; size: 15; tone: "accent" }
                    }
                    Rectangle {
                        visible: utility.busy
                        anchors { bottom: parent.bottom; left: parent.left }
                        width: parent.width * Math.max(0.03, utility.progress)
                        height: 2; radius: 1
                        color: Theme.accent
                        Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Theme.dark ? "#171a20" : "#ffffff"
                    border.color: Theme.separator
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        Rectangle {
                            Layout.fillWidth: true; height: 34
                            color: Theme.dark ? "#22262f" : "#f5f6f8"
                            RowLayout {
                                anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                                Text { Layout.fillWidth: true; text: "NAME"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(10); weight: Font.Bold } }
                                Text { text: "SIZE"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(10); weight: Font.Bold } }
                            }
                        }
                        ListView {
                            id: membersView
                            objectName: "archiveMemberList"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: utility.entries
                            reuseItems: true
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: membersView.width; height: 38
                                color: index % 2 ? (Theme.dark ? "#101215" : "#fbfbfd") : "transparent"
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 15; rightMargin: 18 }
                                    spacing: 8
                                    Symbol { name: modelData.folder ? "folder" : "doc"; size: 16; tone: "gray" }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: Theme.label
                                        elide: Text.ElideMiddle
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                    }
                                    Text {
                                        text: modelData.folder ? "Folder" : utility.sizeText(modelData.size)
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: !utility.entries.length
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: -135
                            text: utility.busy ? "Reading files…" : utility.sourcePath ? "No files to display." : "Choose an archive to see its contents."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: utility.truncated ? "Showing the first 5,000 items" : utility.totalCount
                            ? utility.totalCount + " items" : "ZIP · TAR · GZIP · BZIP2 · XZ"
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "Cancel"
                        visible: utility.busy
                        onClicked: worker.running = false
                    }
                    Button {
                        text: "Extract to…"
                        enabled: utility.sourcePath !== "" && !utility.busy && !utility.error && utility.operation !== "create"
                        onClicked: destinationPicker.open()
                    }
                    Button {
                        text: "Extract"
                        prominent: true
                        enabled: utility.sourcePath !== "" && !utility.busy && !utility.error
                        onClicked: utility.extractTo("")
                    }
                    Button {
                        text: "Show in Files"
                        visible: !!utility.resultPath
                        onClicked: Quickshell.execDetached(["gg-files", "--select", utility.resultPath])
                    }
                }
            }
        }
    }
}
