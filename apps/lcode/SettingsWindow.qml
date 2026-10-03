// LCode ▸ Settings, a window of its own as in Xcode: General, Accounts,
// Behaviors, Themes, Text Editing, Key Bindings, Simulators and Locations.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"
import "settings"

AppWindow {
    id: win
    objectName: "settingsWindow"
    property var app
    property var backend
    readonly property var pages: [
        { title: "General", symbol: "gear", source: "settings/GeneralPage.qml" },
        { title: "Accounts", symbol: "person", source: "settings/AccountsPage.qml" },
        { title: "Behaviors", symbol: "bolt", source: "settings/BehaviorsPage.qml" },
        { title: "Themes", symbol: "palette", source: "settings/ThemesPage.qml" },
        { title: "Text Editing", symbol: "textformat", source: "settings/TextEditingPage.qml" },
        { title: "Key Bindings", symbol: "keyboard", source: "settings/KeyBindingsPage.qml" },
        { title: "Simulators", symbol: "smartphone", source: "settings/SimulatorsPage.qml" },
        { title: "Locations", symbol: "folder", source: "settings/LocationsPage.qml" },
    ]
    readonly property int page: Math.max(0, Math.min(pages.length - 1, app.settingsPage))

    title: "LCode Settings — " + pages[page].title
    implicitWidth: 860
    implicitHeight: 640
    minimumSize: Qt.size(780, 520)
    appearance: app.appearance
    closeAction: () => win.app.settingsOpen = false

    toolbarCenter: [
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: win.pages[win.page].title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
        }
    ]

    Shortcut { sequence: "Ctrl+W"; onActivated: win.app.settingsOpen = false }
    Shortcut { sequence: "Ctrl+]"; onActivated: win.app.settingsPage = (win.page + 1) % win.pages.length }
    Shortcut { sequence: "Ctrl+["; onActivated: win.app.settingsPage = (win.page + win.pages.length - 1) % win.pages.length }

    Item {
        anchors.fill: parent

        // The tabs: icon over label, as in a macOS settings window.
        Row {
            id: tabs
            anchors.horizontalCenter: parent.horizontalCenter
            y: 2
            spacing: 2
            Repeater {
                model: win.pages
                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool current: win.page === index
                    objectName: "settingsTab" + index
                    width: Math.max(78, label.implicitWidth + 18)
                    height: 54
                    radius: 9
                    color: current ? (Theme.dark ? "#26ffffff" : "#12000000") : tabHover.hovered ? (Theme.dark ? "#12ffffff" : "#08000000") : "transparent"
                    Symbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 7
                        name: tab.modelData.symbol
                        size: 22
                        tone: tab.current ? "accent" : "auto"
                    }
                    Text {
                        id: label
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 34
                        text: tab.modelData.title
                        color: tab.current ? Theme.accent : Theme.label
                        font { family: Theme.fontUi; pixelSize: 11; weight: tab.current ? Font.DemiBold : Font.Normal }
                    }
                    HoverHandler { id: tabHover }
                    TapHandler { onTapped: win.app.settingsPage = tab.index }
                }
            }
        }
        Rectangle { id: rule; y: tabs.y + tabs.height + 8; width: parent.width; height: 1; color: Theme.separator }

        Loader {
            id: pageLoader
            objectName: "settingsPage"
            y: rule.y + 1
            width: parent.width
            height: parent.height - y
            // Pages get the app before their bindings first run.
            function load() { setSource(win.pages[win.page].source, { app: win.app, backend: win.backend, overlay: win.overlay }) }
            Component.onCompleted: load()
            Connections {
                target: win
                function onPageChanged() { pageLoader.load() }
            }
        }
    }
}
