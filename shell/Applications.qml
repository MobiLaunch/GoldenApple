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
    // Avoid QWindow.show()/hide() name collisions. Calling those inherited
    // methods can make the layer surface visible without changing our `open`
    // state, which leaves the launcher fully transparent and non-interactive.
    function present() {
        open = true
        console.info("Applications opened; visible desktop entries:", applicationModel.values.length)
        Qt.callLater(() => search.input.forceActiveFocus())
    }
    function dismiss() { open = false; search.text = "" }
    function toggle() { open ? dismiss() : present() }
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
        MouseArea { anchors.fill: parent; onClicked: apps.dismiss() }
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
                    input.Keys.onEscapePressed: apps.dismiss()
                }
            }
            ScriptModel {
                id: applicationModel
                values: {
                    const q = search.text.trim().toLowerCase()
                    return [...DesktopEntries.applications.values]
                        .filter((e) => {
                            if (!e || !e.name || e.noDisplay)
                                return false
                            if (!q)
                                return true
                            const haystack = [
                                String(e.name ?? ""),
                                String(e.genericName ?? ""),
                                String(e.comment ?? ""),
                                String(e.keywords ?? "")
                            ].join(" ").toLowerCase()
                            return haystack.includes(q)
                        })
                        .sort((a, b) => String(a.name).localeCompare(String(b.name)))
                }
            }

            Item {
                visible: applicationModel.values.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    anchors.centerIn: parent
                    width: Math.min(420, parent.width - 40)
                    spacing: 10

                    Symbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: search.text.trim() ? "search" : "apps"
                        size: 46
                        tone: "gray"
                        opacity: 0.78
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: search.text.trim() ? "No Applications Found" : "No Applications Available"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 19; weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: search.text.trim()
                            ? "Try another search."
                            : "Golden Gate could not discover any desktop entries. Run gg-diagnostics and check the Golden Gate shell section."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                }
            }

            GridView {
                id: grid
                visible: applicationModel.values.length > 0
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
                        onClicked: { modelData.execute(); apps.dismiss() }
                    }
                }
            }
        }
    }
}
