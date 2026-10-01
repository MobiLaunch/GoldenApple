// Applications: macOS-style all-apps surface backed by the desktop-entry database.
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.DesktopEntries
import QtQuick
import QtQuick.Layouts
import "theme"
import "components"

PanelWindow {
    id: apps
    property bool open: false
    function show() { open = true; Qt.callLater(() => search.forceActiveFocus()) }
    function hide() { open = false; search.text = "" }
    function toggle() { open ? hide() : show() }
    visible: open || fade.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
        MouseArea { anchors.fill: parent; onClicked: apps.hide() }
    }
    Item {
        anchors { fill: parent; margins: 44 }
        opacity: apps.open ? 1 : 0
        scale: apps.open || Prefs.reduceMotion ? 1 : 0.985
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 210 } }
        Behavior on scale { Spring { spring: Theme.popover } }

        ColumnLayout {
            anchors.fill: parent; spacing: 28
            Glass { variant: "clear";
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(520, parent.width - 40)
                Layout.preferredHeight: 52
                radius: 26
                TextField {
                    id: search
                    anchors { fill: parent; margins: 7 }
                    search: true
                    placeholder: "Search"
                    color: "transparent"
                    border.width: input.activeFocus ? 1.5 : 0
                    border.color: input.activeFocus
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.46)
                        : "transparent"
                    input.font.pixelSize: 17
                    input.Keys.onEscapePressed: apps.hide()
                }
            }
            ScriptModel {
                id: applicationModel
                values: {
                    const q = search.text.trim().toLowerCase()
                    return [...DesktopEntries.applications.values]
                        .filter((e) => e && e.name && (!q
                            || e.name.toLowerCase().includes(q)
                            || (e.genericName ?? "").toLowerCase().includes(q)
                            || (e.keywords ?? []).join(" ").toLowerCase().includes(q)))
                        .sort((a, b) => a.name.localeCompare(b.name))
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true; Layout.fillHeight: true
                cellWidth: Math.max(116, width / Math.max(1, Math.floor(width / 136)))
                cellHeight: 124
                clip: true
                model: applicationModel
                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    scale: !Prefs.reduceMotion && area.pressed ? 0.965 : !Prefs.reduceMotion && area.containsMouse ? 1.025 : 1
                    Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    Column {
                        anchors.centerIn: parent; spacing: 7
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 76; height: 76
                            opacity: area.pressed ? 0.86 : 1
                            Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 70 } }
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
                        onClicked: { modelData.execute(); apps.hide() }
                    }
                }
            }
        }
    }
}
