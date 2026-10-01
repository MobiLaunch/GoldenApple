// Dock: glass shelf with cosine magnification, running indicators, launch
// bounce and tooltips. Pinned apps are desktop-entry ids.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.DesktopEntries
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "theme"
import "components"

PanelWindow {
    id: dock
    property bool liveSession: false
    property var pinned: (liveSession ? ["org.goldengate.Installer"] : []).concat([
        "org.goldengate.Files", "org.goldengate.Web", "org.gnome.Geary", "org.gnome.Fractal", "org.goldengate.Maps",
        "org.goldengate.Photos", "org.goldengate.Music", "org.gnome.Calendar", "org.goldengate.Notes",
        "org.goldengate.Weather", "org.goldengate.Software", "org.goldengate.Settings", "com.mitchellh.ghostty"
    ])
    // Size and magnification from Settings › Desktop & Dock.
    readonly property int tileCount: entries.length + places.length
    readonly property real restingWidth: tileCount * (baseSize + 3) + 25
    property real baseSize: Math.min(Prefs.dockSize, Math.max(16, (width - 48) / (tileCount + 6) - 3))
    // Make magnification visually obvious on real hardware. Settings still gate the effect,
    // but an enabled Dock now reaches ~1.95x at the pointer instead of being capped at 1.8x.
    property real maxSize: Prefs.dockMagnification && !Prefs.reduceMotion
        ? Math.max(baseSize, Math.min(Math.max(Prefs.dockMagnifiedSize, baseSize * 1.95), baseSize * 2.15))
        : baseSize
    property real pointerX: -1
    property real pointerTargetX: -1
    property var launcher: null   // AppLaunch on this screen: the icon grows into the window
    property var applications: null

    function openApplications() {
        if (applications)
            applications.show()
    }

    anchors { bottom: true; left: true; right: true }
    // Include the label, its gap, bounce and spring overshoot inside the layer surface.
    implicitHeight: maxSize + 90
    exclusiveZone: baseSize + 22
    color: "transparent"
    WlrLayershell.namespace: "gg-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Only the shelf (and the magnified icons above it while hovering) take input.
    mask: Region { item: hitbox }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    Process {
        running: true
        command: ["sh", "-c", "test -d /run/archiso && printf yes || true"]
        stdout: StdioCollector { onStreamFinished: dock.liveSession = text.trim() === "yes" }
    }
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
        stdout: StdioCollector { onStreamFinished: dock.trashFull = text.trim().length > 0 }
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: trashCheck.running = true }
    readonly property var places: [
        { name: "Applications", icon: "apps", action: "applications" },
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
        // A Dock click belongs to the Dock's monitor, not whichever monitor last
        // had keyboard focus. This keeps restored windows on the screen clicked.
        const monitor = Hyprland.monitorFor(dock.screen)
        const ws = monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
        Hyprland.dispatch(`movetoworkspace ${ws},address:${t.lastIpcObject.address}`)
        if (monitor?.name) Hyprland.dispatch(`focusmonitor ${monitor.name}`)
    }
    // Magnification targets are measured against resting slot centres. Neither
    // the row nor the shelf changes width while magnifying.
    function centerFor(index) {
        const left = shelf.x + 7
        if (index < entries.length)
            return left + index * (baseSize + 3) + baseSize / 2
        const placeIndex = index - entries.length
        const appWidth = entries.length * (baseSize + 3)
        return left + appWidth + 14 + placeIndex * (baseSize + 3) + baseSize / 2
    }
    function sizeAt(index) {
        if (pointerX < 0 || !Prefs.dockMagnification || Prefs.reduceMotion)
            return baseSize
        const range = baseSize * 2.7
        const d = Math.abs(pointerX - centerFor(index))
        if (d >= range)
            return baseSize
        const influence = Math.pow(Math.cos(d / range * Math.PI / 2), 1.28)
        return baseSize + (maxSize - baseSize) * influence
    }
    function offsetAt(index) {
        if (pointerX < 0 || Prefs.reduceMotion)
            return 0
        const delta = centerFor(index) - pointerX
        if (Math.abs(delta) < 0.5)
            return 0
        return (delta < 0 ? -1 : 1) * (sizeAt(index) - baseSize) * 0.25
    }

    Item {
        id: hitbox
        x: shelf.x; width: shelf.width
        y: hover.hovered ? dock.height - maxSize - 14 : shelf.y
        height: dock.height - y
        HoverHandler {
            id: hover
            // Pointer devices can report substantially faster than the display
            // refresh rate. Record the latest location here and let FrameAnimation
            // apply at most one magnification/layout update per rendered frame.
            onPointChanged: dock.pointerTargetX = hovered ? point.position.x + hitbox.x : -1
            onHoveredChanged: {
                if (!hovered) {
                    dock.pointerTargetX = -1
                    dock.pointerX = -1
                }
            }
        }
        FrameAnimation {
            running: hover.hovered && Prefs.dockMagnification && !Prefs.reduceMotion
            onTriggered: {
                if (dock.pointerX !== dock.pointerTargetX)
                    dock.pointerX = dock.pointerTargetX
            }
        }
    }

    Glass {
        id: shelf
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
        width: row.width + 14
        height: dock.baseSize + 16
        radius: Theme.radiusDock + 2

        Row {
            id: row
            anchors { left: parent.left; leftMargin: 7; bottom: parent.bottom; bottomMargin: 7 }
            spacing: 3
            height: dock.maxSize
            Repeater {
                model: dock.entries
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var wins: dock.windowsFor(modelData)
                    width: dock.baseSize
                    height: row.height

                    SpringValue {
                        id: iconSize
                        target: dock.sizeAt(index)
                        value: dock.baseSize
                        response: 0.19
                        dampingFraction: 0.88
                        epsilon: 0.04
                    }
                    SpringValue {
                        id: iconOffset
                        target: dock.offsetAt(index)
                        value: 0
                        response: 0.20
                        dampingFraction: 0.91
                        epsilon: 0.04
                    }

                    // Calendar apps show today's date, drawn over a date-less icon.
                    readonly property bool calendar: /calendar/i.test(modelData.icon ?? "") && calBlank.loaded

                    Image {
                        id: icon
                        width: iconSize.value; height: iconSize.value
                        x: (tile.width - width) / 2 + iconOffset.value
                        y: tile.height - height
                        z: Math.round(width * 10)
                        source: tile.calendar ? calBlank.source : Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                        sourceSize: Qt.size(dock.maxSize * 2, dock.maxSize * 2)
                        smooth: true; mipmap: true
                        // Pressed, the icon darkens and settles a few percent, without
                        // fighting the Dock's size-based magnification wave.
                        scale: !Prefs.reduceMotion && tipArea.pressed ? 0.955 : 1
                        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 75; easing.type: Easing.OutCubic } }
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
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -6 }
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
                        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : (tip.shown ? 115 : 80) } }
                        Behavior on scale { Spring { spring: Theme.popover } }
                        anchors { bottom: icon.top; bottomMargin: 10 }
                        x: Math.max(8 - (shelf.x + row.x + tile.x), Math.min((parent.width - width) / 2 + iconOffset.value, dock.width - 8 - (shelf.x + row.x + tile.x) - width))
                        width: Math.min(dock.width - 16, tipText.implicitWidth + 24); height: 26; radius: 13
                        tint: Theme.dark ? "#b8282830" : "#c8f4f4f6"
                        Text { id: tipText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 24); elide: Text.ElideRight; textFormat: Text.PlainText; text: tile.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
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
                            } else { if (!Prefs.reduceMotion && Prefs.animateLaunch) bounce.restart(); tile.modelData.execute() }
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
                    width: dock.baseSize
                    height: row.height

                    SpringValue {
                        id: placeSize
                        target: dock.sizeAt(dock.entries.length + index)
                        value: dock.baseSize
                        response: 0.19
                        dampingFraction: 0.88
                        epsilon: 0.04
                    }
                    SpringValue {
                        id: placeOffset
                        target: dock.offsetAt(dock.entries.length + index)
                        value: 0
                        response: 0.20
                        dampingFraction: 0.91
                        epsilon: 0.04
                    }
                    Image {
                        id: placeIcon
                        width: placeSize.value
                        height: placeSize.value
                        x: (place.width - width) / 2 + placeOffset.value
                        y: place.height - height
                        z: Math.round(width * 10)
                        source: place.modelData.action === "applications"
                            ? Qt.resolvedUrl("assets/symbols/apps@accent.svg")
                            : Quickshell.iconPath(place.modelData.icon, "folder")
                        sourceSize: Qt.size(dock.maxSize * 2, dock.maxSize * 2)
                        smooth: true; mipmap: true
                        scale: !Prefs.reduceMotion && placeArea.pressed ? 0.955 : 1
                        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 75; easing.type: Easing.OutCubic } }
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
                        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : (placeTip.shown ? 115 : 80) } }
                        Behavior on scale { Spring { spring: Theme.popover } }
                        anchors { bottom: placeIcon.top; bottomMargin: 10 }
                        x: Math.max(8 - (shelf.x + row.x + place.x), Math.min((parent.width - width) / 2 + placeOffset.value, dock.width - 8 - (shelf.x + row.x + place.x) - width))
                        width: Math.min(dock.width - 16, placeText.implicitWidth + 24); height: 26; radius: 13
                        tint: Theme.dark ? "#b8282830" : "#c8f4f4f6"
                        Text { id: placeText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 24); elide: Text.ElideRight; textFormat: Text.PlainText; text: place.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                    }
                    MouseArea {
                        id: placeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (place.modelData.action === "applications") {
                                dock.openApplications()
                            } else {
                                Quickshell.execDetached(place.modelData.exec)
                            }
                        }
                    }
                }
            }
        }
    }
}

