// Dock: iPad-style glass shelf with fixed-size icons, running indicators,
 // launch bounce and tooltips. Pointer-driven magnification is intentionally
 // absent: the shelf never changes geometry while the pointer moves.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "ui/theme"
import "components"

PanelWindow {
    id: dock
    property bool liveSession: false
    readonly property var defaultPinned: [
        "org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail", "org.goldengate.Messages", "org.goldengate.Maps",
        "org.goldengate.Photos", "org.goldengate.Music", "org.goldengate.Calendar", "org.goldengate.Notes",
        "org.goldengate.Weather", "org.goldengate.Software", "org.goldengate.Settings", "org.goldengate.Terminal"
    ]
    // Keep in Dock / Remove from Dock edit the list in desktop.json (dock.pinned).
    readonly property var keptIds: Prefs.dockPinned ?? defaultPinned
    property var pinned: (liveSession ? ["org.goldengate.Installer"] : []).concat(keptIds.filter((id) => id !== "org.goldengate.Installer"))
    property var notifications: null    // Notification Center, for the red badges
    function keep(entry, on) {
        const ids = keptIds.filter((id) => id !== entry.id)
        if (on) ids.push(entry.id)
        Quickshell.execDetached(["gg-pref", "dock.pinned", JSON.stringify(ids)])
    }
    // Size from Settings › Desktop & Dock. Keep every icon on one stable grid.
    readonly property int tileCount: entries.length + running.length + places.length
    readonly property real restingWidth: tileCount * (baseSize + 6) + 28
    property real baseSize: Math.min(Prefs.dockSize, Math.max(16, (width - 48) / (tileCount + 3) - 6))
    property var launcher: null   // AppLaunch on this screen: the icon grows into the window
    property var applications: null
    property real contextX: 0
    property real contextY: 0
    property var contextItems: []

    function openEntry(entry) {
        const parked = minimizedFor(entry)
        const wins = windowsFor(entry)
        if (parked) restore(parked)
        else if (wins.length) wins[0].activate()
        else entry.execute()
    }

    function quitEntry(entry) {
        const wins = windowsFor(entry)
        // These are Wayland toplevels (windowsFor), which close themselves;
        // they carry no Hyprland IPC object.
        for (let i = 0; i < wins.length; i++) wins[i].close()
    }

    function showEntryMenu(entry, item, localX, localY) {
        const point = item.mapToItem(shelf, localX, localY)
        const wins = windowsFor(entry)
        let menu = [
            { label: wins.length ? "Show" : "Open", action: () => dock.openEntry(entry) }
        ]
        if (wins.length) {
            menu.push("-")
            for (let i = 0; i < wins.length; i++) {
                const win = wins[i]
                menu.push({ label: win.title || entry.name || "Window", action: () => win.activate() })
            }
        }
        menu.push("-")
        const kept = dock.pinned.includes(entry.id)
        if (entry.id !== "org.goldengate.Installer")
            menu.push({ label: kept ? "Remove from Dock" : "Keep in Dock", action: () => dock.keep(entry, !kept) })
        if (wins.length) {
            menu.push("-")
            menu.push({ label: "Quit", shortcut: "⌘Q", action: () => dock.quitEntry(entry) })
        }
        contextItems = menu
        contextX = shelf.x + point.x
        contextY = shelf.y + point.y
        dockMenu.open = true
    }

    function showPlaceMenu(place, item, localX, localY) {
        const point = item.mapToItem(shelf, localX, localY)
        if (place.action === "applications") {
            contextItems = [{ label: "Open Applications", action: () => dock.openApplications() }]
        } else if (place.name === "Downloads") {
            contextItems = [{ label: "Open Downloads", action: () => Quickshell.execDetached(place.exec) }]
        } else {
            contextItems = [
                { label: "Open Trash", action: () => Quickshell.execDetached(place.exec) },
                "-",
                { label: "Empty Trash", enabled: dock.trashFull, action: () => dock.emptyTrash() }
            ]
        }
        contextX = shelf.x + point.x
        contextY = shelf.y + point.y
        dockMenu.open = true
    }

    // Empty Trash, as Files does it (gio knows the trash on every mount).
    function emptyTrash() {
        Quickshell.execDetached(["sh", "-c", "gio trash --empty 2>/dev/null || rm -rf \"${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files/\"* \"${XDG_DATA_HOME:-$HOME/.local/share}/Trash/info/\"*"])
        trashFull = false
    }

    function openApplications() {
        if (applications)
            applications.present()
    }

    anchors { bottom: true; left: true; right: true }
    // Include the label, its gap, bounce and spring overshoot inside the layer surface.
    implicitHeight: baseSize + 70
    exclusiveZone: baseSize + 22
    color: "transparent"
    WlrLayershell.namespace: "gg-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Touch-style shelf: only the shelf itself takes input.
    mask: Region { item: shelf }

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
        { name: "Downloads", icon: "folder", exec: ["gg-files", Quickshell.env("HOME") + "/Downloads"] },
        { name: "Trash", icon: trashFull ? "user-trash-full" : "user-trash", exec: ["gg-files", "trash:"] },
    ]

    // Reading applications.values makes this re-evaluate once the entry scan finishes.
    readonly property var entries: {
        DesktopEntries.applications.values;
        return pinned.map((id) => DesktopEntries.byId(id)).filter((e) => e)
    }
    // Open apps that aren't kept in the Dock, in the order they opened.
    readonly property var running: {
        DesktopEntries.applications.values;
        const out = []
        for (const t of ToplevelManager.toplevels.values) {
            const appId = t.appId ?? ""
            if (!appId) continue
            const entry = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId)
            if (!entry || entry.noDisplay) continue
            if (entries.some((e) => windowsFor(e).includes(t)) || out.includes(entry)) continue
            out.push(entry)
        }
        return out
    }
    function windowsFor(entry) {
        const appId = (entry.id ?? "").toLowerCase()
        const bare = appId.split(".").pop()
        const startup = (entry.startupClass ?? "").toLowerCase()
        return ToplevelManager.toplevels.values.filter((t) => {
            const id = (t.appId ?? "").toLowerCase()
            return id === appId || id === bare || (!!startup && id === startup)
        })
    }
    // A window of this app parked by the yellow light (shell.qml) or ⌘H, to bring back.
    function minimizedFor(entry) {
        const appId = (entry.id ?? "").toLowerCase()
        const bare = appId.split(".").pop()
        const startup = (entry.startupClass ?? "").toLowerCase()
        return Hyprland.toplevels.values.find((t) => {
            // Minimised (yellow light, ⌘M) or hidden (⌘H): both come back on a click.
            if (t.workspace?.name !== "special:minimized" && t.workspace?.name !== "special:hidden") return false
            const cls = (t.wayland?.appId ?? t.lastIpcObject?.class ?? "").toLowerCase()
            return cls === appId || cls === bare || (!!startup && cls === startup)
        })
    }
    function restore(t) {
        // A Dock click belongs to the Dock's monitor, not whichever monitor last
        // had keyboard focus. This keeps restored windows on the screen clicked.
        const monitor = Hyprland.monitorFor(dock.screen)
        const ws = monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
        const address = t.address ? "0x" + t.address.replace(/^0x/, "") : t.lastIpcObject?.address
        if (address) Hyprland.dispatch(`movetoworkspace ${ws},address:${address}`)
        if (monitor?.name) Hyprland.dispatch(`focusmonitor ${monitor.name}`)
    }
    // One app in the Dock: icon, running dot, badge, tooltip, launch bounce.
    component AppTile: Item {
        id: tile
        required property var modelData
        required property int index
        readonly property var wins: dock.windowsFor(modelData)
        width: dock.baseSize
        height: row.height

        // Calendar apps show today's date, drawn over a date-less icon.
        readonly property bool calendar: /calendar/i.test(modelData.icon ?? "") && calBlank.loaded

        Image {
            id: icon
            width: dock.baseSize; height: dock.baseSize
            x: 0
            property real launchOffset: 0
            y: tile.height - height + launchOffset
            z: Math.round(width * 10)
            source: tile.calendar ? calBlank.source : Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
            sourceSize: Qt.size(dock.baseSize * 2, dock.baseSize * 2)
            smooth: true; mipmap: true
            // Pressed, the icon darkens and settles a few percent, without
            // fighting the Dock's size-based magnification wave.
            scale: !Prefs.reduceMotion && tipArea.pressed ? 0.955 : 1
            Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 75; easing.type: Easing.OutCubic } }
            readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
            layer.enabled: gpu && tipArea.pressed
            layer.effect: MultiEffect { brightness: -0.28 }
            opacity: !gpu && tipArea.pressed ? 0.7 : 1
            SequentialAnimation on launchOffset {
                id: bounce
                running: false
                NumberAnimation { to: -22; duration: 165; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 180; easing.type: Easing.InOutQuad }
                NumberAnimation { to: -7; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 120; easing.type: Easing.InOutQuad }
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
        // Unread notifications, as a red badge on the icon's top right.
        readonly property int badge: dock.notifications ? dock.notifications.countFor(modelData.id ?? "", modelData.startupClass ?? "") : 0
        Rectangle {
            visible: tile.badge > 0
            z: 1000
            readonly property real size: Math.max(16, Math.round(dock.baseSize * 0.34))
            x: icon.x + icon.width - width * 0.75
            y: icon.y - height * 0.25
            height: size
            width: Math.max(size, badgeText.implicitWidth + size * 0.6)
            radius: size / 2
            color: Theme.accentRed
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: tile.badge > 99 ? "99+" : tile.badge
                color: "#ffffff"
                font { family: Theme.fontUi; pixelSize: Math.round(parent.size * 0.62); weight: Font.DemiBold }
            }
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
            x: Math.max(8 - (shelf.x + row.x + tile.x), Math.min((parent.width - width) / 2, dock.width - 8 - (shelf.x + row.x + tile.x) - width))
            width: Math.min(dock.width - 16, tipText.implicitWidth + 24); height: 26; radius: 13
            role: "menu"
            Text { id: tipText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 24); elide: Text.ElideRight; textFormat: Text.PlainText; text: tile.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
        }
        MouseArea {
            id: tipArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    dock.showEntryMenu(tile.modelData, tile, mouse.x, mouse.y)
                    return
                }
                const parked = dock.minimizedFor(tile.modelData)
                if (parked) dock.restore(parked)
                else if (tile.wins.length) tile.wins[0].activate()
                else if (dock.launcher?.enabled && Prefs.animateLaunch) {
                    const p = icon.mapToItem(null, 0, 0)
                    dock.launcher.launch(tile.modelData, Qt.rect(p.x, dock.launcher.height - dock.height + p.y, icon.width, icon.height))
                } else {
                    if (!Prefs.reduceMotion && Prefs.animateLaunch) bounce.restart()
                    tile.modelData.execute()
                }
            }
        }
    }

    Glass {
        id: shelf
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
        width: row.width + 18
        height: dock.baseSize + 18
        role: "dock"
        radius: Theme.radiusDock + 2

        Row {
            id: row
            anchors { left: parent.left; leftMargin: 9; bottom: parent.bottom; bottomMargin: 9 }
            spacing: 6
            height: dock.baseSize
            Repeater {
                model: dock.entries
                delegate: AppTile {}
            }
            // Apps running that aren't kept in the Dock, after a divider, as on the Mac.
            Item {
                visible: dock.running.length > 0
                width: 11; height: dock.baseSize
                anchors.bottom: parent.bottom
                Rectangle { anchors.centerIn: parent; width: 1; height: parent.height - 12; color: Theme.dark ? "#40ffffff" : "#2e000000" }
            }
            Repeater {
                model: dock.running
                delegate: AppTile {}
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

                    Image {
                        id: placeIcon
                        width: dock.baseSize
                        height: dock.baseSize
                        x: 0
                        y: place.height - height
                        z: Math.round(width * 10)
                        source: place.modelData.action === "applications"
                            ? Qt.resolvedUrl("assets/symbols/apps@accent.svg")
                            : Quickshell.iconPath(place.modelData.icon, "folder")
                        sourceSize: Qt.size(dock.baseSize * 2, dock.baseSize * 2)
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
                        x: Math.max(8 - (shelf.x + row.x + place.x), Math.min((parent.width - width) / 2, dock.width - 8 - (shelf.x + row.x + place.x) - width))
                        width: Math.min(dock.width - 16, placeText.implicitWidth + 24); height: 26; radius: 13
                        role: "menu"
                        Text { id: placeText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 24); elide: Text.ElideRight; textFormat: Text.PlainText; text: place.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                    }
                    MouseArea {
                        id: placeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                dock.showPlaceMenu(place.modelData, place, mouse.x, mouse.y)
                                return
                            }
                            if (place.modelData.action === "applications")
                                dock.openApplications()
                            else
                                Quickshell.execDetached(place.modelData.exec)
                        }
                    }
                }
            }
        }
    }
    MenuPopup {
        id: dockMenu
        growFrom: Item.BottomLeft
        anchor.window: dock
        anchor.rect.x: Math.max(8, Math.min(dock.contextX, dock.width - menuWidth - 8))
        anchor.rect.y: Math.max(8, dock.contextY - menuHeight - 10)
        items: dock.contextItems
    }
    HyprlandFocusGrab {
        windows: [dockMenu]
        active: dockMenu.open
        onCleared: dockMenu.open = false
    }

}

