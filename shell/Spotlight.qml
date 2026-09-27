// Spotlight: glass search capsule over the desktop. Opens with ⌘Space
// (Hyprland binds SUPER+SPACE to `qs ipc call spotlight toggle`).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "theme"
import "components"

PanelWindow {
    id: spot
    property bool open: false
    function toggle() { open = !open; if (open) { input.text = ""; input.forceActiveFocus() } }

    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "spotlight"
        function toggle(): void { spot.toggle() }
    }

    readonly property var results: {
        const q = input.text.trim().toLowerCase()
        if (!q) return []
        return DesktopEntries.applications.values
            .filter((e) => !e.noDisplay && (e.name.toLowerCase().includes(q) || (e.genericName ?? "").toLowerCase().includes(q)))
            .sort((a, b) => a.name.toLowerCase().indexOf(q) - b.name.toLowerCase().indexOf(q))
            .slice(0, 8)
    }
    property int selected: 0
    function launch(i) { const e = results[i]; if (e) { e.execute(); open = false } }

    MouseArea { anchors.fill: parent; onClicked: spot.open = false }

    ColumnLayout {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.22 }
        width: Math.min(680, parent.width - 32)
        spacing: 10
        scale: spot.open ? 1 : 0.86
        Behavior on scale { Spring { spring: Theme.bouncy } }

        Glass {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            radius: 28
            tint: Theme.glassRegular.tint
            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                spacing: 12
                Symbol { name: "search"; size: 21; tone: "gray" }
                TextInput {
                    id: input
                    Layout.fillWidth: true
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 21 }
                    Keys.onEscapePressed: spot.open = false
                    Keys.onDownPressed: spot.selected = Math.min(spot.results.length - 1, spot.selected + 1)
                    Keys.onUpPressed: spot.selected = Math.max(0, spot.selected - 1)
                    Keys.onReturnPressed: spot.launch(spot.selected)
                    onTextChanged: spot.selected = 0
                    Text {
                        visible: !input.text
                        text: "Spotlight Search"
                        color: Theme.secondaryLabel
                        font: input.font
                    }
                }
            }
        }

        Glass {
            visible: spot.results.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: list.contentHeight + 16
            radius: 24
            tint: Theme.glassRegular.tint
            ListView {
                id: list
                anchors { fill: parent; margins: 8 }
                interactive: false
                model: spot.results
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width; height: 44; radius: 12
                    color: index === spot.selected ? Theme.accent : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Image { source: Quickshell.iconPath(modelData.icon, "application-x-executable"); sourceSize: Qt.size(60, 60); Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                        Text { Layout.fillWidth: true; text: modelData.name; color: index === spot.selected ? "#ffffff" : Theme.label; font { family: Theme.fontUi; pixelSize: 14 } }
                        Text { text: "Application"; color: index === spot.selected ? "#ccffffff" : Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: spot.selected = index; onClicked: spot.launch(index) }
                }
            }
        }
    }
}
