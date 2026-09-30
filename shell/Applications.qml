// Applications: macOS-style all-apps surface backed by the desktop-entry database.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "theme"
import "components"

PanelWindow {
    id: apps
    property bool open: false
    function toggle() { open = !open; if (open) search.forceActiveFocus() }
    visible: open || fade.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gg-applications"
    color: "transparent"
    Item { id: closedMask; width: 0; height: 0; visible: false }
    mask: Region { item: apps.open ? backdrop : closedMask }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.dark ? "#9c121722" : "#78e8edf6"
        opacity: apps.open ? 1 : 0
        Behavior on opacity { NumberAnimation { id: fade; duration: Prefs.reduceMotion ? 1 : 180 } }
        MouseArea { anchors.fill: parent; onClicked: apps.open = false }
    }
    Item {
        anchors { fill: parent; margins: 44 }
        opacity: apps.open ? 1 : 0
        scale: apps.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 210 } }
        Behavior on scale { Spring { spring: Theme.popover } }

        ColumnLayout {
            anchors.fill: parent; spacing: 28
            Glass {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(520, parent.width - 40)
                Layout.preferredHeight: 52; radius: 26
                TextInput {
                    id: search
                    anchors { fill: parent; leftMargin: 46; rightMargin: 18 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.label; selectionColor: Theme.accent
                    font { family: Theme.fontUi; pixelSize: 17 }
                    clip: true
                    Keys.onEscapePressed: apps.open = false
                }
                Symbol { anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }; name: "magnifyingglass"; size: 19; tone: "secondary" }
                Text { anchors { left: parent.left; leftMargin: 46; verticalCenter: parent.verticalCenter }; visible: !search.text && !search.activeFocus; text: "Search"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 17 } }
            }
            GridView {
                id: grid
                Layout.fillWidth: true; Layout.fillHeight: true
                cellWidth: Math.max(116, width / Math.max(1, Math.floor(width / 136)))
                cellHeight: 124
                clip: true
                model: {
                    const q = search.text.trim().toLowerCase()
                    return DesktopEntries.applications.values
                        .filter(e => e && e.name && !e.noDisplay && (!q || e.name.toLowerCase().includes(q)))
                        .sort((a,b) => a.name.localeCompare(b.name))
                }
                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    scale: area.pressed ? 0.91 : area.containsMouse ? 1.035 : 1
                    Behavior on scale { Spring { spring: Theme.snappy } }
                    Column {
                        anchors.centerIn: parent; spacing: 7
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 76; height: 76
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            sourceSize: Qt.size(144,144); smooth: true; mipmap: true
                        }
                        Text {
                            width: Math.min(112, grid.cellWidth - 8); horizontalAlignment: Text.AlignHCenter
                            text: modelData.name; elide: Text.ElideRight; color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                        }
                    }
                    MouseArea {
                        id: area; anchors.fill: parent; hoverEnabled: true
                        onClicked: { modelData.execute(); apps.open = false }
                    }
                }
            }
        }
    }
}
