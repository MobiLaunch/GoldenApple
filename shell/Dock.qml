// Dock: glass shelf with cosine magnification, running indicators, launch
// bounce and tooltips. Pinned apps are desktop-entry ids.
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "theme"
import "components"

PanelWindow {
    id: dock
    property var pinned: [
        "org.gnome.Nautilus", "firefox", "org.gnome.Geary", "org.gnome.Fractal", "org.gnome.Maps",
        "org.gnome.Loupe", "org.gnome.Music", "org.gnome.Calendar", "org.gnome.TextEditor",
        "org.gnome.Weather", "org.gnome.Software", "org.gnome.Settings", "com.mitchellh.ghostty"
    ]
    property real baseSize: Theme.sizeDockIcon
    property real maxSize: Theme.sizeDockMagnified
    property real pointerX: -1

    anchors { bottom: true; left: true; right: true }
    implicitHeight: maxSize + 30
    exclusiveZone: baseSize + 22
    color: "transparent"
    WlrLayershell.namespace: "gg-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Only the shelf (and the magnified icons above it while hovering) take input.
    mask: Region { item: hitbox }

    // Reading applications.values makes this re-evaluate once the entry scan finishes.
    readonly property var entries: {
        DesktopEntries.applications.values;
        return pinned.map((id) => DesktopEntries.byId(id)).filter((e) => e)
    }
    function windowsFor(entry) {
        return ToplevelManager.toplevels.values.filter((t) => t.appId === entry.id || t.appId.toLowerCase() === entry.id.split(".").pop().toLowerCase())
    }
    // Cosine falloff measured against the resting layout, so the Dock never chases itself.
    function sizeAt(index) {
        if (pointerX < 0) return baseSize
        const center = shelf.x + 7 + index * (baseSize + 3) + baseSize / 2
        const range = baseSize * 3.2
        const d = Math.abs(pointerX - center)
        return d >= range ? baseSize : baseSize + (maxSize - baseSize) * Math.pow(Math.cos(d / range * Math.PI / 2), 1.4)
    }

    Item {
        id: hitbox
        x: shelf.x; width: shelf.width
        y: hover.hovered ? 0 : shelf.y; height: dock.height - y
    }

    Glass {
        id: shelf
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
        width: row.width + 14
        height: dock.baseSize + 16
        radius: Theme.radiusDock + 2

        HoverHandler {
            id: hover
            onPointChanged: dock.pointerX = hovered ? point.position.x + shelf.x : -1
            onHoveredChanged: if (!hovered) dock.pointerX = -1
        }

        Row {
            id: row
            anchors { left: parent.left; leftMargin: 7; bottom: parent.bottom; bottomMargin: 7 }
            spacing: 3
            Repeater {
                model: dock.entries
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var wins: dock.windowsFor(modelData)
                    width: dock.sizeAt(index)
                    height: width
                    Behavior on width { enabled: dock.pointerX < 0; Spring { spring: Theme.dock } }

                    Image {
                        id: icon
                        width: parent.width; height: parent.height
                        source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                        sourceSize: Qt.size(dock.maxSize * 2, dock.maxSize * 2)
                        smooth: true; mipmap: true
                        SequentialAnimation on y {
                            id: bounce
                            running: false
                            NumberAnimation { to: -22; duration: 190; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 0; duration: 190; easing.type: Easing.InQuad }
                            NumberAnimation { to: -8; duration: 130; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 0; duration: 130; easing.type: Easing.InQuad }
                        }
                    }
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 2 }
                        width: 4; height: 4; radius: 2
                        color: Theme.dark ? "#ccffffff" : "#8c000000"
                        opacity: tile.wins.length ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                    Glass {
                        id: tip
                        visible: tipArea.containsMouse
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
                        width: tipText.implicitWidth + 24; height: 26; radius: 13
                        tint: Theme.dark ? "#b8282830" : "#c8f4f4f6"
                        Text { id: tipText; anchors.centerIn: parent; text: tile.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                    }
                    MouseArea {
                        id: tipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (tile.wins.length) tile.wins[0].activate()
                            else { bounce.restart(); tile.modelData.execute() }
                        }
                    }
                }
            }
        }
    }
}
