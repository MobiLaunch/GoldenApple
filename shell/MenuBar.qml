// The menu bar: system menu, the app in front and its menus, status items, clock.
// Global application menus need the appmenu D-Bus bridge (see docs/ROADMAP.md);
// until then an app gets Window and Help. With no app in front the desktop is
// Files', and the bar has Files' menus, as the Mac's desktop has Finder's.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "ui/theme"
import "components"
import "ui" as Shared

PanelWindow {
    id: bar
    property var controlCenter
    property var spotlight
    property var session                // SessionDialog: Restart, Shut Down and Log Out ask first
    property var notifications          // the clock opens Notification Center
    property var screenshots            // while recording the screen, a stop button

    // Wi-Fi as the Mac shows it: no item without a Wi-Fi adapter (a wired PC or
    // a VM), a dimmed fan when Wi-Fi is off or not joined to a network, the
    // full fan when connected. NetworkManager's monitor says when to look again.
    property string wifiState: "none"   // "none" | "off" | "disconnected" | "connected"
    Process {
        id: wifiProbe
        running: true
        command: ["nmcli", "-t", "-f", "TYPE,STATE", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = text.split("\n").filter((l) => l.startsWith("wifi:")).map((l) => l.slice(5))
                bar.wifiState = !rows.length ? "none"
                    : rows.some((s) => s === "connected") ? "connected"
                    : rows.every((s) => s === "unavailable") ? "off" : "disconnected"
            }
        }
    }
    Process {
        id: wifiMonitor
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: wifiRefresh.restart() }
        onExited: wifiRetry.start()
    }
    Timer { id: wifiRefresh; interval: 400; onTriggered: wifiProbe.running = true }
    Timer { id: wifiRetry; interval: 30000; onTriggered: { wifiProbe.running = true; wifiMonitor.running = true } }

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.sizeMenubar
    exclusiveZone: implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "gg-menubar"
    // What its glass bends: the desktop under it.
    DesktopBackdrop { surface: bar; namespace: "gg-menubar" }
    WlrLayershell.layer: WlrLayer.Top

    // Liquid Glass (docs/LIQUID-GLASS.md). With its background on (the
    // default), a frosted band in the appearance's colours, as the Mac's menu
    // bar has been; off, a faint film over the wallpaper, as macOS 26 can
    // show it. HyprGlass turns either into blurred glass. Reduce Transparency
    // makes it solid.
    readonly property bool band: Prefs.menuBarBackground || Prefs.reduceTransparency
    Rectangle {
        anchors.fill: parent
        color: Prefs.reduceTransparency ? (Theme.dark ? "#f21e1e20" : "#f2f4f4f6")
             : Prefs.menuBarBackground ? (Theme.dark ? "#8c1c1c20" : "#b8f2f2f5") : "#14ffffff"
        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : 175 } }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: bar.band ? Theme.separator : "#2effffff"
        }
    }

    // The film is so faint the wallpaper still decides the text: each half
    // picks white or dark text from its brightness (sampled once per wallpaper).
    property string wallpaper: Prefs.wallpaper
    readonly property bool darkLeft: band ? !Theme.dark : wallpaperDarkLeft
    readonly property bool darkRight: band ? !Theme.dark : wallpaperDarkRight
    Canvas {
        id: sampler
        visible: false
        width: 96; height: 60
        Component.onCompleted: loadImage(bar.wallpaper)
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            if (!isImageLoaded(bar.wallpaper)) return;
            ctx.drawImage(bar.wallpaper, 0, 0, width, height);
            const lum = (x0, x1) => {
                const d = ctx.getImageData(x0, 0, x1 - x0, 3).data;
                let t = 0;
                for (let i = 0; i < d.length; i += 4) t += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255;
                return t / (d.length / 4);
            };
            bar.wallpaperDarkLeft = lum(0, width * 0.45) > 0.66;
            bar.wallpaperDarkRight = lum(width * 0.55, width) > 0.66;
        }
    }
    property bool wallpaperDarkLeft: false
    property bool wallpaperDarkRight: false

    readonly property var active: ToplevelManager.activeToplevel
    readonly property string appName: {
        if (!active) return "Files";
        const entry = DesktopEntries.byId(active.appId);
        return entry ? entry.name : active.appId;
    }

    // A menu bar item: a capsule lights up under it while pressed and while
    // its menu is open, and the item dips a little as you press it.
    component BarItem: Item {
        id: item
        property bool highlighted: false
        default property alias content: row.data
        signal clicked()
        implicitWidth: row.implicitWidth + 18
        implicitHeight: 24
        // The menu bar has no hover state; an open or pressed item sits on a
        // plain white capsule, not glass and not the accent.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width; height: 22
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.22)
            opacity: item.highlighted || barTap.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : (item.highlighted || barTap.pressed ? 60 : 150) } }
        }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6
            scale: !Prefs.reduceMotion && barTap.pressed ? 0.965 : !Prefs.reduceMotion && barTap.containsMouse ? 1.012 : 1
            Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
        }
        MouseArea { id: barTap; anchors.fill: parent; hoverEnabled: true; onClicked: item.clicked() }
    }
    component BarText: Text {
        property bool dark: false
        color: dark ? "#d6000000" : "#ffffff"
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
        // Soft legibility shadow on the GPU renderer (shader effects need it).
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#38001440"; shadowBlur: 0.5; shadowVerticalOffset: 0 }
    }

    // Room on the bar: the status items on the right come first (they're
    // what you check); the app's menus get what's left. The app's name is
    // shortened with an ellipsis past what fits, and menus that don't fit
    // move into »: a menu of their titles, each opening its own menu beside
    // it (by pointer, or Down/Right/Return).
    FontMetrics { id: titleMetrics; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium } }
    FontMetrics { id: appMetrics; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold } }
    // On a very narrow screen the status items give way too, keeping the
    // logo, the app's name (at least 40 px) and » on the bar.
    readonly property real statusRoom: Math.max(0, Math.min(statusRow.implicitWidth, bar.width - 26 - 24 - 40 - 56))
    readonly property real leftRoom: bar.width - statusRoom - 40
    readonly property real appNatural: appMetrics.advanceWidth(bar.appName) + 18
    readonly property int titlesShown: {
        const reserve = 26 + Math.min(appNatural, 120)                  // the logo, and the name at least this wide
        let used = reserve, n = 0
        for (const t of bar.titles) {
            const w = titleMetrics.advanceWidth(t) + 19
            const more = n + 1 < bar.titles.length ? 24 : 0              // room for » if any are left
            if (used + w + more > leftRoom) break
            used += w; n++
        }
        return n
    }
    readonly property real titlesWidth: bar.titles.slice(0, titlesShown).reduce((a, t) => a + titleMetrics.advanceWidth(t) + 19, 0)
        + (titlesShown < bar.titles.length ? 24 : 0)

    RowLayout {
        id: titlesRow
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 1
        BarItem {
            id: logo
            highlighted: systemMenu.open
            onClicked: bar.openMenu("system")
            Symbol { name: "logo"; size: 18; tone: bar.darkLeft ? "dark" : "white" }
        }
        BarItem {
            id: appItem
            highlighted: appMenu.open
            onClicked: bar.openMenu("app")
            BarText {
                text: bar.appName; font.weight: Font.Bold; dark: bar.darkLeft
                elide: Text.ElideRight
                Layout.maximumWidth: Math.max(40, bar.leftRoom - 26 - bar.titlesWidth - 18)
            }
        }
        Repeater {
            model: bar.titles.slice(0, bar.titlesShown)
            delegate: BarItem {
                id: titleItem
                required property string modelData
                highlighted: modelData === "Window" ? windowMenu.open : barMenu.open && bar.openTitle === modelData
                onClicked: bar.openMenu(modelData)
                Component.onCompleted: if (modelData === "Window") bar.windowItem = titleItem
                BarText { text: titleItem.modelData; dark: bar.darkLeft }
            }
        }
        BarItem {
            id: overflowItem
            objectName: "menuBarOverflow"
            readonly property var hidden: bar.titles.slice(bar.titlesShown)
            visible: hidden.length > 0
            highlighted: barMenu.open && (bar.openTitle === "»" || hidden.includes(bar.openTitle)) || windowMenu.open && hidden.includes("Window")
            onClicked: bar.openMenu("»")
            Component.onCompleted: if (visible && hidden.includes("Window")) bar.windowItem = overflowItem
            onHiddenChanged: if (hidden.includes("Window")) bar.windowItem = overflowItem
            BarText { text: "»"; dark: bar.darkLeft }
        }
    }

    // The status items, clipped from the left when there isn't room for all
    // (the clock and Control Center, on the right, always stay).
    Item {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: bar.statusRoom
        height: statusRow.implicitHeight
        clip: width < statusRow.implicitWidth
        RowLayout {
            id: statusRow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 1
            // Recording the screen (⇧⌘5): stop, as on the Mac.
            BarItem {
                visible: bar.screenshots?.recording ?? false
                onClicked: bar.screenshots.stopRecording()
                Rectangle {
                    implicitWidth: 17; implicitHeight: 17; radius: 8.5
                    color: "transparent"
                    border { width: 1.4; color: bar.darkRight ? "#d6000000" : "#ffffff" }
                    Rectangle { anchors.centerIn: parent; width: 6.5; height: 6.5; radius: 1.2; color: bar.darkRight ? "#d6000000" : "#ffffff" }
                }
            }
            // Now Playing (Control Center settings): the playing track's title.
            BarItem {
                id: nowPlaying
                readonly property var player: Mpris.players.values.find((p) => p.isPlaying) ?? null
                // The first to go on a narrow bar.
                visible: Prefs.barNowPlaying && !!player && bar.width >= 1000
                onClicked: bar.controlCenter.toggle()
                RowLayout {
                    spacing: 5
                    Symbol { name: "music"; size: 14; tone: bar.darkRight ? "dark" : "white" }
                    BarText {
                        Layout.maximumWidth: 180
                        text: nowPlaying.player?.trackTitle ?? ""
                        elide: Text.ElideRight
                        dark: bar.darkRight
                    }
                }
            }
            // Focus: the moon while Do Not Disturb is on.
            BarItem {
                visible: Prefs.barFocus && Prefs.focusDnd
                onClicked: bar.controlCenter.toggle()
                Symbol { name: "moon"; size: 15; tone: bar.darkRight ? "dark" : "white" }
            }
            BarItem {
                id: batteryItem
                visible: Prefs.barBattery && Battery.present
                highlighted: batteryMenu.open
                // Its menu, as on the Mac: the charge and time left, the power
                // source, and Battery settings.
                onClicked: {
                    bar.batteryMenuX = batteryItem.mapToItem(bar.contentItem, 0, 0).x
                    batteryMenu.open = !batteryMenu.open
                }
                // Drawn in the bar's ink (dark over a light wallpaper), red when low
                // and not charging. The level is the firmware's (Battery.qml).
                RowLayout {
                    id: battery
                    readonly property color ink: bar.darkRight ? "#000000" : "#ffffff"
                    readonly property real level: Battery.level
                    readonly property bool charging: Battery.charging
                    spacing: 1
                    BarText {
                        visible: Prefs.barBatteryPercent
                        Layout.rightMargin: 4
                        text: Battery.percent + "%"
                        dark: bar.darkRight
                    }
                    Rectangle {
                        implicitWidth: 25; implicitHeight: 12; radius: 4
                        color: "transparent"; border.width: 1.2
                        border.color: Qt.rgba(battery.ink.r, battery.ink.g, battery.ink.b, 0.45)
                        Rectangle {
                            x: 2.5; y: 2.5; height: parent.height - 5; radius: 1.8
                            color: battery.level <= 0.1 && !battery.charging ? Theme.accentRed : battery.ink
                            width: Math.max(1.5, (parent.width - 5) * battery.level)
                        }
                    }
                    Rectangle { implicitWidth: 1.8; implicitHeight: 4.5; color: Qt.rgba(battery.ink.r, battery.ink.g, battery.ink.b, 0.45) }
                }
            }
            // Bluetooth and Sound (Control Center settings), each opening its
            // Control Center list.
            BarItem {
                visible: Prefs.barBluetooth && !!Bluetooth.defaultAdapter
                Symbol {
                    name: "bluetooth"; size: 15; tone: bar.darkRight ? "dark" : "white"
                    opacity: (Bluetooth.defaultAdapter?.enabled ?? false) ? 1 : 0.35
                }
                onClicked: {
                    if (!bar.controlCenter.open) bar.controlCenter.toggle()
                    bar.controlCenter.showDetail("bluetooth")
                }
            }
            BarItem {
                id: soundItem
                readonly property var sink: Pipewire.defaultAudioSink
                visible: Prefs.barSound && !!sink
                PwObjectTracker { objects: [soundItem.sink] }
                Symbol {
                    name: (soundItem.sink?.audio?.muted ?? false) || (soundItem.sink?.audio?.volume ?? 1) === 0 ? "speaker" : "speaker-wave"
                    size: 15; tone: bar.darkRight ? "dark" : "white"
                }
                onClicked: {
                    if (!bar.controlCenter.open) bar.controlCenter.toggle()
                    bar.controlCenter.showDetail("sound")
                }
            }
            BarItem {
                visible: Prefs.barWifi && bar.wifiState !== "none"
                Symbol {
                    name: "wifi"; size: 16; tone: bar.darkRight ? "dark" : "white"
                    opacity: bar.wifiState === "connected" ? 1 : 0.35
                }
                onClicked: {
                    if (!bar.controlCenter.open) bar.controlCenter.toggle()
                    bar.controlCenter.showDetail("wifi")
                }
            }
            BarItem { visible: Prefs.barSpotlight; Symbol { name: "search"; size: 15; tone: bar.darkRight ? "dark" : "white" } onClicked: bar.spotlight.toggle() }
            BarItem {
                visible: Prefs.barCitron
                Accessible.name: "Citron Intelligence"
                Shared.Symbol { name: "wand"; size: 15; tone: bar.darkRight ? "dark" : "white" }
                onClicked: Quickshell.execDetached(["gg-intelligence"])
            }
            // Privacy: a dot while an app uses the microphone (yellow), camera
            // (green) or screen (purple), an arrow while one is given your location
            // (blue). Each grows in and out; Control Center names the apps.
            BarItem {
                visible: privacyRow.width > 0.5
                onClicked: bar.controlCenter.toggle()
                Row {
                    id: privacyRow
                    spacing: 0
                    Repeater {
                        model: ["location", "screen", "camera", "mic"]
                        delegate: Item {
                            required property string modelData
                            readonly property bool on: Privacy[modelData].length > 0
                            width: on ? (modelData === "location" ? 15 : 12) : 0
                            height: 16
                            clip: true
                            Behavior on width { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                            Accessible.name: Privacy.names[modelData] + " in use"
                            // Location: the Mac's filled arrow.
                            Canvas {
                                visible: parent.modelData === "location"
                                anchors.centerIn: parent
                                width: 11; height: 11
                                scale: parent.on ? 1 : 0.4
                                Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 225; easing.type: Easing.OutBack } }
                                onPaint: {
                                    const c = getContext("2d")
                                    c.reset()
                                    c.fillStyle = Privacy.colors.location
                                    c.beginPath(); c.moveTo(10.5, 0.5); c.lineTo(0.5, 4.8); c.lineTo(5.2, 5.8); c.lineTo(6.2, 10.5); c.closePath(); c.fill()
                                }
                            }
                            Rectangle {
                                visible: parent.modelData !== "location"
                                anchors.centerIn: parent
                                width: 7; height: 7; radius: 3.5
                                color: Privacy.colors[parent.modelData]
                                border { width: 0.5; color: Qt.rgba(0, 0, 0, 0.18) }
                                scale: parent.on ? 1 : 0.2
                                Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 225; easing.type: Easing.OutBack } }
                            }
                        }
                    }
                }
            }
            BarItem {
                highlighted: bar.controlCenter.open
                onClicked: bar.controlCenter.toggle()
                Symbol { name: "control-center"; size: 16; tone: bar.darkRight ? "dark" : "white" }
            }
            BarItem {
                highlighted: bar.notifications?.centerOpen ?? false
                onClicked: if (bar.notifications) bar.notifications.centerOpen = !bar.notifications.centerOpen
                SystemClock { id: clock; precision: Prefs.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes }
                BarText { text: Qt.formatDateTime(clock.date, bar.clockFormat); dark: bar.darkRight }
            }
        }
    }

    MenuPopup {
        id: systemMenu
        instant: true
        anchor.window: bar
        anchor.rect.x: logo.x + 8
        anchor.rect.y: bar.height + 5
        items: [
            { label: "About This Computer", action: () => Hyprland.dispatch("exec gg-settings about") },
            "-",
            { label: "System Settings…", shortcut: "⌘,", action: () => Hyprland.dispatch("exec gg-settings") },
            { label: "Software…", action: () => Hyprland.dispatch("exec gg-software") },
            "-",
            { label: "Force Quit…", shortcut: "⌥⌘⎋", action: () => Hyprland.dispatch("exec hyprctl kill") },
            "-",
            { label: "Sleep", action: () => Hyprland.dispatch("exec systemctl suspend") },
            { label: "Restart…", action: () => bar.session?.ask("restart") },
            { label: "Shut Down…", action: () => bar.session?.ask("shutdown") },
            "-",
            { label: "Lock Screen", shortcut: "⌃⌘Q", action: () => Hyprland.dispatch("exec loginctl lock-session") },
            { label: "Log Out…", shortcut: "⇧⌘Q", action: () => bar.session?.ask("logout") }
        ]
    }
    HyprlandFocusGrab {
        windows: [systemMenu]
        active: systemMenu.open && !systemMenu.reopening
        onCleared: if (!systemMenu.reopening && !systemMenu.suppressClear) systemMenu.open = false
    }

    // The app's own menu, under its name: Hide and Quit for the app in front
    // (every one of its windows), as the Mac's application menu has them.
    readonly property var appWindows: active ? ToplevelManager.toplevels.values.filter((t) => t.appId === active.appId) : []
    MenuPopup {
        id: appMenu
        instant: true
        anchor.window: bar
        anchor.rect.x: appItem.x + 8
        anchor.rect.y: bar.height + 5
        items: bar.active ? [
            { label: "Hide " + bar.appName, shortcut: "⌘H", action: () => Hyprland.dispatch("movetoworkspacesilent special:hidden,class:^(" + String(bar.active.appId).replace(/[.^$*+?()[\]{}|\\]/g, "\\$&") + ")$") },
            { label: "Hide Others", shortcut: "⌥⌘H", action: () => bar.hideOthers(String(bar.active.appId)) },
            { label: "Show All", enabled: bar.hiddenWindows().length > 0, action: () => bar.showAll() },
            "-",
            { label: "Quit " + bar.appName, shortcut: "⌘Q", action: () => bar.appWindows.forEach((w) => w.close()) }
        ] : [
            { label: "About Files", action: () => Hyprland.dispatch("exec gg-settings about") },
            "-",
            { label: "Settings…", shortcut: "⌘,", action: () => Hyprland.dispatch("exec gg-settings dock") },
            "-",
            { label: "Empty Trash…", action: () => bar.emptyTrash() },
            "-",
            { label: "Hide Others", shortcut: "⌥⌘H", action: () => bar.hideOthers("") },
            { label: "Show All", enabled: bar.hiddenWindows().length > 0, action: () => bar.showAll() }
        ]
    }
    HyprlandFocusGrab {
        windows: [appMenu]
        active: appMenu.open && !appMenu.reopening
        onCleared: if (!appMenu.reopening && !appMenu.suppressClear) appMenu.open = false
    }

    // Window: the Mac's Window menu with Sequoia's Move & Resize, for the window
    // in front. gg-tile is told its address, since this menu holds the focus
    // while it's open.
    property string tileTarget: ""
    property Item windowItem
    // A second click on an open menu's title closes it, as on the Mac.
    function openMenu(name) {
        const key = name === "window" ? "Window" : name
        const wasOpen = key === "system" ? systemMenu.open : key === "app" ? appMenu.open
            : key === "Window" ? windowMenu.open : barMenu.open && openTitle === key
        systemMenu.open = !wasOpen && key === "system"
        appMenu.open = !wasOpen && key === "app"
        if ((key === "Window" || key === "»") && !wasOpen) tileTarget = activeAddress()
        windowMenu.open = !wasOpen && key === "Window"
        const item = titleItems().find((i) => i.modelData === key)
            ?? (key === "»" || overflowItem.hidden.includes(key) ? overflowItem : null)
        if (!wasOpen && item && key !== "Window") {
            openTitle = key
            barMenuX = item.x + titlesRow.x
        }
        barMenu.open = !wasOpen && !!item && key !== "Window"
    }
    function titleItems() {
        return Array.from(titlesRow.children).filter((c) => c.modelData !== undefined)
    }
    function activeAddress() {
        const a = Hyprland.activeToplevel?.address ?? ""
        return a ? "0x" + String(a).replace(/^0x/, "") : ""
    }
    // Hide Others, Show All and Bring All to Front, as the Mac's app and
    // Window menus have them. Hidden windows wait on special:hidden (⌘H),
    // minimised ones on special:minimized; the Dock brings either back.
    function windowClass(t) { return String(t.wayland?.appId ?? t.lastIpcObject?.class ?? "") }
    function windowAddress(t) { return t.address ? "0x" + String(t.address).replace(/^0x/, "") : "" }
    function hiddenWindows() { return Hyprland.toplevels.values.filter((t) => t.workspace?.name === "special:hidden") }
    function minimizedWindows() { return Hyprland.toplevels.values.filter((t) => t.workspace?.name === "special:minimized") }
    function hideOthers(keep) {
        const ws = Hyprland.focusedWorkspace?.id
        for (const t of Hyprland.toplevels.values) {
            if (t.workspace?.id !== ws || windowClass(t) === keep || !windowAddress(t)) continue
            Hyprland.dispatch("movetoworkspacesilent special:hidden,address:" + windowAddress(t))
        }
    }
    function showAll(minimizedToo) {
        const ws = Hyprland.focusedWorkspace?.id ?? 1
        for (const t of hiddenWindows().concat(minimizedToo ? minimizedWindows() : []))
            if (windowAddress(t)) Hyprland.dispatch("movetoworkspacesilent " + ws + ",address:" + windowAddress(t))
    }
    function bringToFront(appId) {
        const ws = Hyprland.focusedWorkspace?.id ?? 1
        for (const t of Hyprland.toplevels.values)
            if (windowClass(t) === appId && windowAddress(t) && t.workspace?.id !== ws)
                Hyprland.dispatch("movetoworkspacesilent " + ws + ",address:" + windowAddress(t))
        if (tileTarget) Hyprland.dispatch("focuswindow address:" + tileTarget)
    }
    function tile(layout) { Hyprland.dispatch("exec gg-tile " + layout + (tileTarget ? " " + tileTarget : "")) }
    function minimize() { Hyprland.dispatch("movetoworkspacesilent special:minimized" + (tileTarget ? ",address:" + tileTarget : "")) }
    // Full screen and Zoom act on the focused window: focus it first.
    function fullscreen(mode) {
        if (tileTarget) Hyprland.dispatch("focuswindow address:" + tileTarget)
        Hyprland.dispatch("fullscreen " + mode)
    }
    MenuPopup {
        id: windowMenu
        instant: true
        anchor.window: bar
        anchor.rect.x: (bar.windowItem ? bar.windowItem.x + titlesRow.x : 0)
        anchor.rect.y: bar.height + 5
        items: !bar.active ? [
            { label: "Minimize", shortcut: "⌘M", enabled: false },
            { label: "Zoom", enabled: false },
            "-",
            { label: "Mission Control", action: () => bar.shell("missioncontrol toggle") },
            { label: "Bring All to Front", enabled: bar.minimizedWindows().length > 0, action: () => bar.showAll(true) }
        ] : [
            { label: "Minimize", shortcut: "⌘M", action: () => bar.minimize() },
            { label: "Zoom", shortcut: "⌥⌘F", action: () => bar.fullscreen(1) },
            "-",
            { label: "Fill", shortcut: "⌃⌥↩", symbol: "tile-fill", action: () => bar.tile("fill") },
            { label: "Center", shortcut: "⌃⌥C", symbol: "tile-center", action: () => bar.tile("center") },
            "-",
            { header: "Move & Resize" },
            { label: "Left", shortcut: "⌃⌥←", symbol: "tile-left", action: () => bar.tile("left") },
            { label: "Right", shortcut: "⌃⌥→", symbol: "tile-right", action: () => bar.tile("right") },
            { label: "Top", shortcut: "⌃⌥↑", symbol: "tile-top", action: () => bar.tile("top") },
            { label: "Bottom", shortcut: "⌃⌥↓", symbol: "tile-bottom", action: () => bar.tile("bottom") },
            "-",
            { label: "Top Left", shortcut: "⌃⌥U", symbol: "tile-top-left", action: () => bar.tile("top-left") },
            { label: "Top Right", shortcut: "⌃⌥I", symbol: "tile-top-right", action: () => bar.tile("top-right") },
            { label: "Bottom Left", shortcut: "⌃⌥J", symbol: "tile-bottom-left", action: () => bar.tile("bottom-left") },
            { label: "Bottom Right", shortcut: "⌃⌥K", symbol: "tile-bottom-right", action: () => bar.tile("bottom-right") },
            "-",
            { label: "Return to Previous Size", shortcut: "⌃⌥⌫", action: () => bar.tile("restore") },
            "-",
            { label: "Enter Full Screen", shortcut: "⌃⌘F", action: () => bar.fullscreen(0) },
            "-",
            { label: "Bring All to Front", action: () => bar.bringToFront(String(bar.active.appId)) }
        ]
    }
    HyprlandFocusGrab {
        windows: [windowMenu]
        active: windowMenu.open && !windowMenu.reopening
        onCleared: if (!windowMenu.reopening && !windowMenu.suppressClear) windowMenu.open = false
    }

    // Menus after the app's name. An app's own menus need the appmenu bridge.
    readonly property var titles: active ? ["Window", "Help"] : ["File", "Edit", "View", "Go", "Window", "Help"]
    property string openTitle: ""
    property real barMenuX: 0
    readonly property string home: Quickshell.env("HOME")
    // Settings → Menu Bar → Clock.
    readonly property string clockFormat: [Prefs.clockShowDay ? "ddd" : "", Prefs.clockShowDate ? "MMM d" : ""].filter((x) => x).join(" ")
        + "   " + (Prefs.clock24 ? "HH:mm" : "h:mm") + (Prefs.clockSeconds ? ":ss" : "") + (Prefs.clock24 ? "" : " AP")
    function shell(call) { Hyprland.dispatch("exec qs -c golden-gate ipc call " + call) }
    function files(path) { Quickshell.execDetached(["gg-files", path]) }
    function emptyTrash() { Trash.empty() }
    function menuItems(title) {
        if (title === "»") return overflowItem.hidden.map((t) => ({ label: t, submenu: t === "Window" ? windowMenu.items : bar.menuItems(t) }))
        if (title === "File") return [
            { label: "New Files Window", shortcut: "⌘N", action: () => bar.files(bar.home) },
            { label: "New Folder on Desktop", action: () => Quickshell.execDetached(["sh", "-c",
                'd="$HOME/Desktop/untitled folder"; n=2; while [ -e "$d" ]; do d="$HOME/Desktop/untitled folder $n"; n=$((n+1)); done; mkdir -p "$d" && exec gg-files --select "$d"']) },
            "-",
            { label: "Open Recents", action: () => bar.files("recents:") },
            "-",
            { label: "Find…", shortcut: "⌘Space", action: () => bar.spotlight.toggle() }
        ]
        if (title === "Edit") return [
            { label: "Undo", shortcut: "⌘Z", enabled: false },
            { label: "Redo", shortcut: "⇧⌘Z", enabled: false },
            "-",
            { label: "Cut", shortcut: "⌘X", enabled: false },
            { label: "Copy", shortcut: "⌘C", enabled: false },
            { label: "Paste", shortcut: "⌘V", enabled: false },
            { label: "Select All", shortcut: "⌘A", enabled: false }
        ]
        if (title === "View") return [
            { label: "Edit Widgets…", action: () => bar.shell("widgets edit") },
            "-",
            { label: "Show Launchpad", action: () => bar.shell("launchpad toggle") },
            { label: "Mission Control", action: () => bar.shell("missioncontrol toggle") },
            "-",
            { label: "Show Notification Center", action: () => { if (bar.notifications) bar.notifications.centerOpen = true } }
        ]
        if (title === "Go") return [
            { label: "Recents", symbol: "clock", action: () => bar.files("recents:") },
            { label: "Documents", symbol: "doc", action: () => bar.files(bar.home + "/Documents") },
            { label: "Desktop", symbol: "wallpaper", action: () => bar.files(bar.home + "/Desktop") },
            { label: "Downloads", symbol: "download", action: () => bar.files(bar.home + "/Downloads") },
            { label: "Home", symbol: "house", action: () => bar.files(bar.home) },
            "-",
            { label: "AirDrop", symbol: "broadcast", action: () => Quickshell.execDetached(["gg-airdrop"]) },
            { label: "Applications", symbol: "apps", action: () => bar.shell("launchpad toggle") },
            "-",
            { label: "Trash", symbol: "trash", action: () => bar.files("trash:") }
        ]
        if (title === "Help") return [
            { label: "Search", action: () => bar.spotlight.toggle() },
            "-",
            { label: "Keyboard Shortcuts", action: () => Hyprland.dispatch("exec gg-settings keyboard") },
            { label: "Ask Citron…", action: () => Quickshell.execDetached(["gg-intelligence"]) }
        ]
        return []
    }
    property real batteryMenuX: 0
    MenuPopup {
        id: batteryMenu
        objectName: "batteryMenu"
        instant: true
        anchor.window: bar
        anchor.rect.x: Math.min(bar.batteryMenuX, bar.width - menuWidth - 8)
        anchor.rect.y: bar.height + 5
        items: [
            { header: "Battery" },
            { text: Battery.percent + "%", shortcut: Battery.timeText, enabled: false },
            { text: "Power Source: " + Battery.sourceText, enabled: false },
            "-",
            { text: "Show Percentage in Menu Bar", checked: Prefs.barBatteryPercent,
              action: () => Quickshell.execDetached(["gg-pref", "menuBar.items.batteryPercent", Prefs.barBatteryPercent ? "false" : "true"]) },
            { text: "Battery Settings…", action: () => Quickshell.execDetached(["gg-settings", "battery"]) }
        ]
    }
    HyprlandFocusGrab {
        windows: [batteryMenu]
        active: batteryMenu.open && !batteryMenu.reopening
        onCleared: if (!batteryMenu.reopening && !batteryMenu.suppressClear) batteryMenu.open = false
    }
    MenuPopup {
        id: barMenu
        objectName: "menuBarMenu"
        instant: true
        anchor.window: bar
        anchor.rect.x: bar.barMenuX + 8
        anchor.rect.y: bar.height + 5
        items: bar.menuItems(bar.openTitle)
    }
    HyprlandFocusGrab {
        windows: [barMenu]
        active: barMenu.open && !barMenu.reopening
        onCleared: if (!barMenu.reopening && !barMenu.suppressClear) barMenu.open = false
    }
}
