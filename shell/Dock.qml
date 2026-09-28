// Dock: glass shelf with cosine magnification, running indicators, launch
// bounce and tooltips. Pinned apps are desktop-entry ids.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "theme"
import "components"

PanelWindow {
    id: dock
    property var pinned: [
        "org.gnome.Nautilus", "firefox", "org.gnome.Geary", "org.gnome.Fractal", "org.goldengate.Maps",
        "org.goldengate.Photos", "org.goldengate.Music", "org.gnome.Calendar", "org.goldengate.Notes",
        "org.goldengate.Weather", "org.gnome.Software", "org.goldengate.Settings", "com.mitchellh.ghostty"
    ]
    // Size and magnification from Settings › Desktop & Dock.
    property real baseSize: Prefs.dockSize
    property real maxSize: Prefs.dockMagnification && !Prefs.reduceMotion ? Prefs.dockMagnifiedSize : Prefs.dockSize
    property real pointerX: -1
    property var launcher: null   // AppLaunch on this screen: the icon grows into the window

    anchors { bottom: true; left: true; right: true }
    implicitHeight: maxSize + 30
    exclusiveZone: baseSize + 22
    color: "transparent"
    WlrLayershell.namespace: "gg-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Only the shelf (and the magnified icons above it while hovering) take input.
    mask: Region { item: hitbox }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    // Written by icons/build.mjs unless a custom Calendar icon replaces the default.
    Image {
        id: calBlank
        readonly property bool loaded: status === Image.Ready
        visible: false
        source: Qt.resolvedUrl("assets/calendar-blank.svg")
    }

    // Right of the separator: Downloads and the Trash (full or empty).
    property bool trashFull: false
    Process {
        id: trashCheck
        running: true
        command: ["sh", "-c", "ls -A \"${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files\" 2>/dev/null | head -1"]
        stdout: SplitParser { onRead: (line) => dock.trashFull = line.length > 0 }
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: trashCheck.running = true }
    readonly property var places: [
        { name: "Downloads", icon: "folder", exec: ["xdg-open", Quickshell.env("HOME") + "/Downloads"] },
        { name: "Trash", icon: trashFull ? "user-trash-full" : "user-trash", exec: ["xdg-open", "trash:///"] },
    ]

    // Reading applications.values makes this re-evaluate once the entry scan finishes.
    readonly property var entries: {
        DesktopEntries.applications.values;
        return pinned.map((id) => DesktopEntries.byId(id)).filter((e) => e)
    }
    function windowsFor(entry) {
        return ToplevelManager.toplevels.values.filter((t) => t.appId === entry.id || t.appId.toLowerCase() === entry.id.split(".").pop().toLowerCase())
    }
    // A window of this app parked by the yellow light (shell.qml), to bring back.
    function minimizedFor(entry) {
        const bare = entry.id.split(".").pop().toLowerCase()
        return Hyprland.toplevels.values.find((t) => t.workspace?.name === "special:minimized"
            && (t.lastIpcObject?.class === entry.id || (t.lastIpcObject?.class ?? "").toLowerCase() === bare))
    }
    function restore(t) {
        const ws = Hyprland.focusedWorkspace?.id ?? 1
        Hyprland.dispatch(`movetoworkspace ${ws},address:${t.lastIpcObject.address}`)
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

                    // Calendar apps show today's date, drawn over a date-less icon.
                    readonly property bool calendar: /calendar/i.test(modelData.icon ?? "") && calBlank.loaded

                    Image {
                        id: icon
                        width: parent.width; height: parent.height
                        source: tile.calendar ? calBlank.source : Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                        sourceSize: Qt.size(dock.maxSize * 2, dock.maxSize * 2)
                        smooth: true; mipmap: true
                        // Pressed, the icon darkens as on the Mac (dims without shaders).
                        readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
                        layer.enabled: gpu && tipArea.pressed
                        layer.effect: MultiEffect { brightness: -0.28 }
                        opacity: !gpu && tipArea.pressed ? 0.7 : 1
                        SequentialAnimation on y {
                            id: bounce
                            running: false
                            NumberAnimation { to: -22; duration: 190; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 0; duration: 190; easing.type: Easing.InQuad }
                            NumberAnimation { to: -8; duration: 130; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 0; duration: 130; easing.type: Easing.InQuad }
                        }
                        Text {
                            visible: tile.calendar
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height * 0.30 - baselineOffset
                            text: Qt.formatDate(clock.date, "ddd").toUpperCase()
                            color: "#ff3b30"
                            font { family: Theme.fontUi; pixelSize: Math.max(6, Math.round(parent.height * 0.13)); weight: Font.DemiBold; letterSpacing: 0.5 }
                        }
                        Text {
                            visible: tile.calendar
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height * 0.76 - baselineOffset
                            text: clock.date.getDate()
                            color: "#1c1c1e"
                            font { family: Theme.fontUi; pixelSize: Math.max(12, Math.round(parent.height * 0.46)); weight: Font.Light; letterSpacing: -2 }
                        }
                    }
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 2 }
                        width: 4; height: 4; radius: 2
                        color: Theme.dark ? "#ccffffff" : "#8c000000"
                        opacity: tile.wins.length && Prefs.dockIndicators ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                    Glass {
                        id: tip
                        readonly property bool shown: tipArea.containsMouse && !tipArea.pressed
                        visible: opacity > 0
                        opacity: shown ? 1 : 0
                        scale: shown ? 1 : 0.9
                        transformOrigin: Item.Bottom
                        Behavior on opacity { NumberAnimation { duration: tip.shown ? 140 : 90 } }
                        Behavior on scale { Spring { spring: Theme.popover } }
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
                            const parked = dock.minimizedFor(tile.modelData)
                            if (parked) dock.restore(parked)
                            else if (tile.wins.length) tile.wins[0].activate()
                            else if (dock.launcher?.enabled && Prefs.animateLaunch) {
                                // The Dock window sits at the bottom of the launcher's full-screen one.
                                const p = icon.mapToItem(null, 0, 0)
                                dock.launcher.launch(tile.modelData, Qt.rect(p.x, dock.launcher.height - dock.height + p.y, icon.width, icon.height))
                            } else { bounce.restart(); tile.modelData.execute() }
                        }
                    }
                }
            }
            Item {
                width: 11; height: dock.baseSize
                anchors.bottom: parent.bottom
                Rectangle { anchors.centerIn: parent; width: 1; height: parent.height - 12; color: Theme.dark ? "#40ffffff" : "#2e000000" }
            }
            Repeater {
                model: dock.places
                delegate: Item {
                    id: place
                    required property var modelData
                    required property int index
                    width: dock.sizeAt(dock.entries.length + index + 0.35)
                    height: width
                    Behavior on width { enabled: dock.pointerX < 0; Spring { spring: Theme.dock } }
                    Image {
                        anchors.fill: parent
                        source: Quickshell.iconPath(place.modelData.icon, "folder")
                        sourceSize: Qt.size(dock.maxSize * 2, dock.maxSize * 2)
                        smooth: true; mipmap: true
                        readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
                        layer.enabled: gpu && placeArea.pressed
                        layer.effect: MultiEffect { brightness: -0.28 }
                        opacity: !gpu && placeArea.pressed ? 0.7 : 1
                    }
                    Glass {
                        id: placeTip
                        readonly property bool shown: placeArea.containsMouse && !placeArea.pressed
                        visible: opacity > 0
                        opacity: shown ? 1 : 0
                        scale: shown ? 1 : 0.9
                        transformOrigin: Item.Bottom
                        Behavior on opacity { NumberAnimation { duration: placeTip.shown ? 140 : 90 } }
                        Behavior on scale { Spring { spring: Theme.popover } }
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
                        width: placeText.implicitWidth + 24; height: 26; radius: 13
                        tint: Theme.dark ? "#b8282830" : "#c8f4f4f6"
                        Text { id: placeText; anchors.centerIn: parent; text: place.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                    }
                    MouseArea { id: placeArea; anchors.fill: parent; hoverEnabled: true; onClicked: Quickshell.execDetached(place.modelData.exec) }
                }
            }
        }
    }
}
