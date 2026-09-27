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
import "theme"
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

    readonly property var active: ToplevelManager.activeToplevel
    readonly property string appName: {
        if (!active) return "Files";
        const entry = DesktopEntries.byId(active.appId);
        return entry ? entry.name : active.appId;
    }

    component BarItem: Rectangle {
        id: item
        property bool highlighted: false
        default property alias content: row.data
        signal clicked()
        implicitWidth: row.implicitWidth + 18
        implicitHeight: 24
        radius: 12
        color: highlighted ? Qt.rgba(1, 1, 1, 0.26) : "transparent"
        border.width: highlighted ? 0.5 : 0
        border.color: Qt.rgba(1, 1, 1, 0.55)
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout { id: row; anchors.centerIn: parent; spacing: 6 }
        MouseArea { anchors.fill: parent; onClicked: item.clicked() }
    }
    component BarText: Text {
        color: "#ffffff"
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
            Symbol { name: "logo"; size: 18 }
        }
        BarItem {
            BarText { text: bar.appName; font.weight: Font.Bold }
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
        BarItem { Symbol { name: "wifi"; size: 16 } onClicked: bar.controlCenter.toggle() }
        BarItem { Symbol { name: "search"; size: 15 } onClicked: bar.spotlight.toggle() }
        BarItem {
            highlighted: bar.controlCenter.open
            onClicked: bar.controlCenter.toggle()
            Symbol { name: "control-center"; size: 16 }
        }
        BarItem {
            SystemClock { id: clock; precision: SystemClock.Minutes }
            BarText { text: Qt.formatDateTime(clock.date, "ddd MMM d   h:mm AP") }
        }
    }

    MenuPopup {
        id: systemMenu
        anchor.window: bar
        anchor.rect.x: logo.x + 8
        anchor.rect.y: bar.height + 5
        items: [
            { label: "About This Computer", action: () => Hyprland.dispatch("exec gnome-control-center system") },
            "-",
            { label: "System Settings…", shortcut: "⌘,", action: () => Hyprland.dispatch("exec gnome-control-center") },
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
