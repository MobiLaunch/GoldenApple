// Notification server + glass banners (replaces mako). Banners slide in from the
// right, can be swiped away, expire on their own, and show app actions.
// Focus (Do Not Disturb) keeps notifications but suppresses banners.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"

PanelWindow {
    id: root
    readonly property bool dnd: Prefs.focusDnd
    readonly property var list: server.trackedNotifications.values

    anchors { top: true; right: true }
    margins { top: 8; right: 10 }
    implicitWidth: 360
    implicitHeight: Math.max(1, column.implicitHeight + 4)
    exclusionMode: ExclusionMode.Normal   // sit below the menu bar
    color: "transparent"
    visible: !dnd && list.length > 0
    WlrLayershell.namespace: "gg-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region { item: column }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false
        onNotification: (n) => { n.tracked = true }
    }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { Quickshell.execDetached(["gg-pref", "focus.dnd", root.dnd ? "false" : "true"]) }
        function setDnd(on: bool): void { Quickshell.execDetached(["gg-pref", "focus.dnd", on ? "true" : "false"]) }
        function clear(): void { root.list.slice().forEach((n) => n.dismiss()) }
    }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: root.list.slice(0, 4)
            delegate: Glass { variant: "clear";
                id: banner
                required property var modelData
                readonly property var n: modelData
                Layout.fillWidth: true
                Layout.preferredHeight: content.implicitHeight + 24
                radius: 22
                tint: Theme.glassRegular.tint
                // Slide in from the right; follows the finger/pointer when swiped.
                property real dragX: 0
                property bool shown: false
                x: (shown ? 0 : width + 20) + dragX
                opacity: 1 - Math.max(0, dragX) / 320
                Behavior on x { enabled: !drag.active; Spring { spring: Theme.snappy } }
                Component.onCompleted: shown = true

                Timer {
                    interval: banner.n.expireTimeout > 0 ? banner.n.expireTimeout * 1000 : 5500
                    running: !hover.hovered && !banner.n.resident && banner.n.expireTimeout !== 0
                    onTriggered: banner.n.expire()
                }
                HoverHandler { id: hover }
                DragHandler {
                    id: drag
                    target: null
                    xAxis.enabled: true; yAxis.enabled: false
                    onTranslationChanged: banner.dragX = Math.max(-20, translation.x)
                    onActiveChanged: if (!active) { if (banner.dragX > 110) banner.n.dismiss(); else banner.dragX = 0 }
                }

                RowLayout {
                    id: content
                    anchors { fill: parent; margins: 12; leftMargin: 14 }
                    spacing: 11
                    Item {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 36; Layout.preferredHeight: 36
                        // The notification's image, else the sender's icon, else a bell tile.
                        // iconPath(…, true) returns "" for a missing icon instead of Qt's checkerboard.
                        readonly property string resolved: {
                            if (banner.n.image) return banner.n.image
                            const entry = banner.n.appName ? DesktopEntries.heuristicLookup(banner.n.appName) : null
                            for (const name of [banner.n.appIcon, banner.n.desktopEntry, entry?.icon ?? ""]) {
                                const path = name ? Quickshell.iconPath(name, true) : ""
                                if (path) return path
                            }
                            return ""
                        }
                        Image { anchors.fill: parent; sourceSize: Qt.size(72, 72); source: parent.resolved; visible: parent.resolved !== "" }
                        Rectangle {
                            anchors.fill: parent; radius: 9
                            visible: parent.resolved === ""
                            gradient: Gradient { GradientStop { position: 0; color: "#ff6b5f" } GradientStop { position: 1; color: "#ff2d55" } }
                            Symbol { anchors.centerIn: parent; name: "bell"; size: 20; tone: "white" }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            Text { Layout.fillWidth: true; text: banner.n.summary; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                            Text { text: "now"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 } }
                        }
                        Text { Layout.fillWidth: true; text: banner.n.body; textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                        RowLayout {
                            visible: banner.n.actions.length > 0
                            Layout.topMargin: 6
                            spacing: 6
                            Repeater {
                                model: banner.n.actions
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26; radius: 13
                                    color: Theme.fill
                                    Text { anchors.centerIn: parent; text: modelData.text; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                                    MouseArea { anchors.fill: parent; onClicked: modelData.invoke() }
                                }
                            }
                        }
                    }
                }
                // Close button appears on hover, top-left like the system banners.
                Glass { variant: "clear";
                    x: -7; y: -7; width: 22; height: 22; radius: 11
                    tint: Theme.glassRegular.tint
                    opacity: hover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Symbol { anchors.centerIn: parent; name: "xmark"; size: 10; tone: Theme.dark ? "white" : "dark" }
                    MouseArea { anchors.fill: parent; onClicked: banner.n.dismiss() }
                }
            }
        }
    }
}

