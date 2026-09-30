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

    visible: open || closeTimer.running
    onOpenChanged: if (!open) closeTimer.restart()
    Timer { id: closeTimer; interval: Prefs.reduceMotion ? 1 : 150 }
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
            // GNOME Settings opens Golden Gate's own (gnome-control-center wrapper): list it once.
            .filter((e) => !e.noDisplay && e.id !== "org.gnome.Settings" && (e.name.toLowerCase().includes(q) || (e.genericName ?? "").toLowerCase().includes(q) || (e.keywords ?? []).some((k) => k.toLowerCase().startsWith(q))))
            .sort((a, b) => { const at = (e) => { const i = e.name.toLowerCase().indexOf(q); return i < 0 ? 99 : i }; return at(a) - at(b) })
            .slice(0, 8)
    }
    property int selected: 0
    property var launchers: []
    function launch(i) {
        const e = results[i]
        if (!e) return
        const l = launchers.find((x) => x.screen === spot.screen) ?? launchers[0]
        const row = list.itemAtIndex(i)
        if (l?.enabled && row) {
            // Spotlight covers its screen, so the row icon's position is already in screen space.
            const icon = row.appIcon, p = icon.mapToItem(null, 0, 0)
            l.launch(e, Qt.rect(p.x, p.y, icon.width, icon.height))
        } else e.execute()
        open = false
    }

    MouseArea { anchors.fill: parent; onClicked: spot.open = false }

    ColumnLayout {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.22 }
        width: Math.min(680, parent.width - 32)
        spacing: 10
        opacity: spot.open ? 1 : 0
        scale: spot.open ? 1 : 0.975
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 140; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.popover } }

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
                    clip: true
                    selectByMouse: true
                    Accessible.name: "Spotlight Search"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 21 }
                    Keys.onEscapePressed: spot.open = false
                    Keys.onDownPressed: spot.selected = Math.max(0, Math.min(spot.results.length - 1, spot.selected + 1))
                    Keys.onUpPressed: spot.selected = Math.max(0, spot.selected - 1)
                    Keys.onReturnPressed: spot.launch(spot.selected)
                    onTextChanged: spot.selected = 0
                    Text {
                        visible: !input.text && !input.preeditText
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
            Layout.preferredHeight: Math.min(list.contentHeight + 16, Math.max(60, spot.height * 0.78 - 90))
            radius: 24
            tint: Theme.glassRegular.tint
            ListView {
                id: list
                anchors { fill: parent; margins: 8 }
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: spot.selected
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                model: spot.results
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property Item appIcon: rowIcon
                    width: list.width; height: 44; radius: 12
                    color: index === spot.selected ? Theme.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: Prefs.reduceMotion ? 1 : 80 } }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Image {
                            id: rowIcon
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            sourceSize: Qt.size(60, 60)
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            scale: index === spot.selected && !Prefs.reduceMotion ? 1.055 : 1
                            Behavior on scale { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 85; easing.type: Easing.OutCubic } }
                        }
                        Text { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight; color: index === spot.selected ? "#ffffff" : Theme.label; font { family: Theme.fontUi; pixelSize: 14 } }
                        Text { text: "Application"; color: index === spot.selected ? "#ccffffff" : Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: spot.selected = index; onClicked: spot.launch(index) }
                }
            }
        }
    }
}

