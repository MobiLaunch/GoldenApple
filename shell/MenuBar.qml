// Transparent menu bar: system menu, the focused app's name, status items, clock.
// Global application menus need the appmenu D-Bus bridge (see docs/ROADMAP.md);
// until then the bar shows the app name without its menus.
import Quickshell
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

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.sizeMenubar
    exclusiveZone: implicitHeight
    color: "transparent"
    WlrLayershell.namespace: "gg-menubar"
    WlrLayershell.layer: WlrLayer.Top

    // The bar has no material, so each half picks white or dark text from the
    // brightness of the wallpaper behind it (sampled once per wallpaper).
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
            onClicked: systemMenu.open = !systemMenu.open
            Symbol { name: "logo"; size: 18; tone: bar.darkLeft ? "dark" : "white" }
        }
        BarItem {
            BarText { text: bar.appName; font.weight: Font.Bold; dark: bar.darkLeft }
        }
    }

    RowLayout {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 1
        BarItem {
            visible: UPower.displayDevice.isLaptopBattery
            RowLayout {
                spacing: 1
                Rectangle {
                    implicitWidth: 25; implicitHeight: 12; radius: 4
                    color: "transparent"; border.width: 1.2; border.color: Qt.rgba(1, 1, 1, 0.55)
                    Rectangle {
                        x: 2.5; y: 2.5; height: parent.height - 5; radius: 1.8; color: "#ffffff"
                        width: (parent.width - 5) * UPower.displayDevice.percentage
                    }
                }
                Rectangle { implicitWidth: 1.8; implicitHeight: 4.5; color: Qt.rgba(1, 1, 1, 0.55) }
            }
        }
        BarItem { Symbol { name: "wifi"; size: 16; tone: bar.darkRight ? "dark" : "white" } onClicked: bar.controlCenter.toggle() }
        BarItem { Symbol { name: "search"; size: 15; tone: bar.darkRight ? "dark" : "white" } onClicked: bar.spotlight.toggle() }
        BarItem {
            highlighted: bar.controlCenter.open
            onClicked: bar.controlCenter.toggle()
            Symbol { name: "control-center"; size: 16; tone: bar.darkRight ? "dark" : "white" }
        }
        BarItem {
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
            { label: "Software…", action: () => Hyprland.dispatch("exec gnome-software") },
            "-",
            { label: "Force Quit…", shortcut: "⌥⌘⎋", action: () => Hyprland.dispatch("exec hyprctl kill") },
            "-",
            { label: "Sleep", action: () => Hyprland.dispatch("exec systemctl suspend") },
            { label: "Restart…", action: () => Hyprland.dispatch("exec systemctl reboot") },
            { label: "Shut Down…", action: () => Hyprland.dispatch("exec systemctl poweroff") },
            "-",
            { label: "Lock Screen", shortcut: "⌃⌘Q", action: () => Hyprland.dispatch("exec loginctl lock-session") },
            { label: "Log Out…", shortcut: "⇧⌘Q", action: () => Hyprland.dispatch("exit") }
        ]
    }
    HyprlandFocusGrab {
        windows: [systemMenu]
        active: systemMenu.open
        onCleared: systemMenu.open = false
    }
}
