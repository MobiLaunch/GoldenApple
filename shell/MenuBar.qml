// Transparent menu bar: system menu, the focused app's name, status items, clock.
// Global application menus need the appmenu D-Bus bridge (see docs/ROADMAP.md);
// until then the bar shows the app name without its menus.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "ui/theme"
import "components"

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
    WlrLayershell.layer: WlrLayer.Top

    // Liquid Glass (docs/LIQUID-GLASS.md): a faint white film that HyprGlass
    // turns into blurred glass, with a lit hairline along the bottom. Reduce
    // Transparency makes it solid.
    Rectangle {
        anchors.fill: parent
        color: Prefs.reduceTransparency ? (Theme.dark ? "#f21e1e20" : "#f2f4f4f6") : "#14ffffff"
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Prefs.reduceTransparency ? Theme.separator : "#2effffff"
        }
    }

    // The film is so faint the wallpaper still decides the text: each half
    // picks white or dark text from its brightness (sampled once per wallpaper).
    property string wallpaper: Prefs.wallpaper
    property bool darkLeft: false
    property bool darkRight: false
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
            bar.darkLeft = lum(0, width * 0.45) > 0.66;
            bar.darkRight = lum(width * 0.55, width) > 0.66;
        }
    }

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
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
        // Soft legibility shadow on the GPU renderer (shader effects need it).
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#38001440"; shadowBlur: 0.5; shadowVerticalOffset: 0 }
    }

    RowLayout {
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 1
        BarItem {
            id: logo
            highlighted: systemMenu.open
            onClicked: { appMenu.open = false; windowMenu.open = false; systemMenu.open = !systemMenu.open }
            Symbol { name: "logo"; size: 18; tone: bar.darkLeft ? "dark" : "white" }
        }
        BarItem {
            id: appItem
            highlighted: appMenu.open
            onClicked: { systemMenu.open = false; windowMenu.open = false; appMenu.open = !appMenu.open }
            BarText { text: bar.appName; font.weight: Font.Bold; dark: bar.darkLeft }
        }
        BarItem {
            id: windowItem
            visible: !!bar.active
            highlighted: windowMenu.open
            onClicked: {
                systemMenu.open = false; appMenu.open = false
                if (!windowMenu.open) bar.tileTarget = bar.activeAddress()
                windowMenu.open = !windowMenu.open
            }
            BarText { text: "Window"; dark: bar.darkLeft }
        }
    }

    RowLayout {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
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
        BarItem {
            visible: UPower.displayDevice.isLaptopBattery
            // Drawn in the bar's ink (dark over a light wallpaper), red when low
            // and not charging.
            RowLayout {
                id: battery
                readonly property color ink: bar.darkRight ? "#000000" : "#ffffff"
                readonly property real level: UPower.displayDevice.percentage
                readonly property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging
                    || UPower.displayDevice.state === UPowerDeviceState.FullyCharged
                spacing: 1
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
        BarItem {
            visible: bar.wifiState !== "none"
            Symbol {
                name: "wifi"; size: 16; tone: bar.darkRight ? "dark" : "white"
                opacity: bar.wifiState === "connected" ? 1 : 0.35
            }
            onClicked: {
                if (!bar.controlCenter.open) bar.controlCenter.toggle()
                bar.controlCenter.showDetail("wifi")
            }
        }
        BarItem { Symbol { name: "search"; size: 15; tone: bar.darkRight ? "dark" : "white" } onClicked: bar.spotlight.toggle() }
        BarItem {
            highlighted: bar.controlCenter.open
            onClicked: bar.controlCenter.toggle()
            Symbol { name: "control-center"; size: 16; tone: bar.darkRight ? "dark" : "white" }
        }
        BarItem {
            highlighted: bar.notifications?.centerOpen ?? false
            onClicked: if (bar.notifications) bar.notifications.centerOpen = !bar.notifications.centerOpen
            SystemClock { id: clock; precision: SystemClock.Minutes }
            BarText { text: Qt.formatDateTime(clock.date, "ddd MMM d   h:mm AP"); dark: bar.darkRight }
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
        active: systemMenu.open
        onCleared: systemMenu.open = false
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
            "-",
            { label: "Quit " + bar.appName, shortcut: "⌘Q", action: () => bar.appWindows.forEach((w) => w.close()) }
        ] : [
            { label: "New Files Window", shortcut: "⌘N", action: () => Hyprland.dispatch("exec gg-files") },
            "-",
            { label: "Open Launchpad", action: () => Hyprland.dispatch("exec qs -c golden-gate ipc call launchpad toggle") }
        ]
    }
    HyprlandFocusGrab {
        windows: [appMenu]
        active: appMenu.open
        onCleared: appMenu.open = false
    }

    // Window: the Mac's Window menu with Sequoia's Move & Resize, for the window
    // in front. gg-tile is told its address, since this menu holds the focus
    // while it's open.
    property string tileTarget: ""
    function openMenu(name) {
        systemMenu.open = name === "system"
        appMenu.open = name === "app"
        if (name === "window" && !windowMenu.open) tileTarget = activeAddress()
        windowMenu.open = name === "window" && !!active
    }
    function activeAddress() {
        const a = Hyprland.activeToplevel?.address ?? ""
        return a ? "0x" + String(a).replace(/^0x/, "") : ""
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
        anchor.rect.x: windowItem.x + 8
        anchor.rect.y: bar.height + 5
        items: [
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
            { label: "Enter Full Screen", shortcut: "⌃⌘F", action: () => bar.fullscreen(0) }
        ]
    }
    HyprlandFocusGrab {
        windows: [windowMenu]
        active: windowMenu.open
        onCleared: windowMenu.open = false
    }
}
