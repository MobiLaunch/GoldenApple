// "Welcome to LCode": create, clone or open a project; recent projects in the
// trailing glass sidebar.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"

AppWindow {
    id: win
    objectName: "welcome"
    property var app
    property var backend
    title: "Welcome to LCode"
    // New Project's template gallery needs more room than the welcome page.
    implicitWidth: newProject.shown ? 880 : 820
    implicitHeight: newProject.shown ? 660 : 500
    minimumSize: Qt.size(820, 500)
    resizable: false
    trailingSidebarWidth: 300
    background: Theme.windowBg
    appearance: app.appearance
    Shortcut { sequences: win.app.keysFor("settings"); onActivated: win.app.openSettings() }

    component Action: Item {
        id: action
        property string symbol
        property string title
        property string detail
        signal triggered()
        width: 360
        height: 52
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: hover.hovered ? Theme.fill : "transparent"
        }
        Symbol { x: 14; anchors.verticalCenter: parent.verticalCenter; name: action.symbol; size: 24; tone: "accent" }
        Column {
            x: 52
            anchors.verticalCenter: parent.verticalCenter
            Text { text: action.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold } }
            Text { text: action.detail; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
        }
        HoverHandler { id: hover }
        TapHandler { onTapped: action.triggered() }
    }

    Item {
        anchors.fill: parent
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            spacing: 4
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 112; height: 112
                sourceSize: Qt.size(224, 224)
                source: Quickshell.iconPath("org.goldengate.LCode", true)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "LCode"
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 34; weight: Font.Light }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Version 26.0"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }
            Item { width: 1; height: 12 }
            Action {
                anchors.horizontalCenter: parent.horizontalCenter
                symbol: "plus"
                title: "Create New Project…"
                detail: "Design an app, or start from a Swift, Python, Rust or C template"
                onTriggered: newProject.open()
            }
            Action {
                anchors.horizontalCenter: parent.horizontalCenter
                symbol: "download"
                title: "Clone Git Repository…"
                detail: "Start working on something from a Git repository"
                onTriggered: clone.open()
            }
            Action {
                anchors.horizontalCenter: parent.horizontalCenter
                symbol: "folder"
                title: "Open Existing Project…"
                detail: "Browse your projects"
                onTriggered: openPanel.open()
            }
        }
        Checkbox {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
            width: 270
            text: "Show this window when LCode opens"
            checked: win.app.settings.showWelcome !== false
            onToggled: (on) => win.app.saveSettings({ showWelcome: on })
        }
    }

    trailingSidebar: [
        Item {
            anchors.fill: parent
            ListView {
                id: recents
                anchors.fill: parent
                clip: true
                spacing: 2
                model: win.app.settings.recent || []
                delegate: Item {
                    id: recent
                    required property string modelData
                    width: recents.width
                    height: 50
                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: recentHover.hovered ? Theme.selection : "transparent"
                    }
                    Image {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32
                        sourceSize: Qt.size(64, 64)
                        source: Quickshell.iconPath("org.goldengate.LCode", true)
                    }
                    Column {
                        x: 48
                        width: parent.width - 56
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            text: recent.modelData.split("/").pop()
                            elide: Text.ElideRight
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            text: recent.modelData.replace(Quickshell.env("HOME"), "~")
                            elide: Text.ElideMiddle
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                    }
                    HoverHandler { id: recentHover }
                    TapHandler { onTapped: win.app.openProject(recent.modelData) }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: (p) => menu.popup(recent, p.position.x, p.position.y, [
                            { text: "Open", action: () => win.app.openProject(recent.modelData) },
                            { text: "Show in Files", action: () => Quickshell.execDetached(["gg-files", recent.modelData]) },
                            { separator: true },
                            { text: "Remove from Recents", action: () => win.backend.call("recent", { action: "remove", path: recent.modelData },
                                (r) => { if (r.ok) win.app.settings = Object.assign({}, win.app.settings, { recent: r.recent }) }) },
                        ])
                    }
                }
            }
            EmptyState {
                anchors.fill: parent
                visible: recents.count === 0
                symbol: "clock"
                title: "No Recent Projects"
            }
        }
    ]

    PopupMenu { id: menu; parent: win.overlay }

    NewProjectSheet {
        id: newProject
        objectName: "newProjectSheet"
        parent: win.overlay
        app: win.app
        backend: win.backend
        onCreated: (root) => win.app.openProject(root)
    }

    OpenPanel {
        id: openPanel
        parent: win.overlay
        backend: win.backend
        onChosen: (path) => win.app.openProject(path)
    }

    Sheet {
        id: clone
        parent: win.overlay
        panelWidth: 620
        property string error: ""
        property bool working: false
        onShownChanged: if (shown) { error = ""; urlField.text = ""; urlField.input.forceActiveFocus() }
        Column {
            width: parent.width
            spacing: 12
            Text { text: "Clone a Git Repository"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold } }
            TextField { id: urlField; width: parent.width; height: 30; placeholder: "https://github.com/owner/repository.git" }
            Text { text: "Clone into:"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
            FolderBrowser { id: cloneBrowser; width: parent.width; height: 220; backend: win.backend }
            Text {
                visible: !!clone.error || clone.working
                width: parent.width
                wrapMode: Text.WordWrap
                text: clone.working ? "Cloning…" : clone.error
                color: clone.working ? Theme.secondaryLabel : "#ff453a"
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancel"; onClicked: clone.close() }
                Button {
                    text: "Clone"
                    prominent: true
                    enabled: urlField.text.trim().length > 0 && !clone.working
                    onClicked: {
                        clone.working = true
                        win.backend.call("clone", { url: urlField.text, parent: cloneBrowser.selected || cloneBrowser.path }, (r) => {
                            clone.working = false
                            if (!r.ok) { clone.error = r.error; return }
                            clone.close()
                            win.app.openProject(r.root)
                        })
                    }
                }
            }
        }
    }

    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: newProject.open() }
    Shortcut { sequence: "Ctrl+O"; onActivated: openPanel.open() }
}
