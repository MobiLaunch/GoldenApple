// The green button's menu, as macOS Sequoia shows it while the pointer rests
// on the button: Move & Resize as a grid of tiles (halves, then quarters),
// Fill & Arrange, then Full Screen and Return to Previous Size. AppWindow opens
// it from TrafficLights; each tile runs gg-tile on this window, which is the
// focused one once the pointer has clicked in it.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "theme"

Item {
    id: menu
    anchors.fill: parent
    visible: box.opacity > 0
    z: 101
    property bool open: false
    property bool hovered: hover.hovered
    property real anchorX: 0
    property real anchorY: 0

    // For screenshots (tools/preview): open from the start.
    Component.onCompleted: if (Quickshell.env("GG_ZOOM_MENU_PREVIEW") === "1") open = true

    function run(command) {
        open = false
        Hyprland.dispatch("exec " + command)
    }

    Glass {
        id: box
        role: "menu"
        radius: Theme.radiusMenu
        // Over the window's own content, which nothing blurs: the menu's
        // material at the opacity Reduce Transparency gives it.
        tint: Qt.rgba(Theme.menu.tint.r, Theme.menu.tint.g, Theme.menu.tint.b, Theme.menu.reduced)
        x: Math.max(6, Math.min(menu.anchorX - 14, menu.width - width - 6))
        y: menu.anchorY
        width: 4 * 44 + 3 * 4 + 2 * pad
        height: col.implicitHeight + 2 * pad
        readonly property real pad: 8
        transformOrigin: Item.TopLeft
        opacity: menu.open ? 1 : 0
        scale: menu.open || Theme.reduceMotion ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : (menu.open ? 120 : 160) } }
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : Theme.popover.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.popover.curve } }

        HoverHandler { id: hover }

        component Heading: Text {
            leftPadding: 6
            topPadding: 2; bottomPadding: 5
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
        }
        component Tile: Rectangle {
            id: tile
            property string layout
            property string symbol
            property string tip
            width: 44; height: 32
            radius: 7
            color: tap.pressed ? Theme.accent : tileHover.hovered ? (Theme.dark ? "#1fffffff" : "#14000000") : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 80 } }
            Symbol {
                anchors.centerIn: parent
                name: tile.symbol; size: 22
                tone: tap.pressed ? "white" : tileHover.hovered ? "accent" : "auto"
            }
            HoverHandler { id: tileHover; onHoveredChanged: if (hovered) hint.text = tile.tip }
            TapHandler { id: tap; onTapped: menu.run("gg-tile " + tile.layout) }
            Accessible.role: Accessible.Button
            Accessible.name: tile.tip
        }
        component MenuRow: Rectangle {
            id: item
            property string text
            property string command
            width: parent.width; height: 24
            radius: Theme.radiusMenuItem
            color: rowHover.hovered ? Theme.accent : "transparent"
            Text {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                text: item.text
                color: rowHover.hovered ? "#ffffff" : Theme.label
                font { family: Theme.fontUi; pixelSize: 13 }
            }
            HoverHandler { id: rowHover }
            TapHandler { onTapped: menu.run(item.command) }
        }

        Column {
            id: col
            x: box.pad; y: box.pad
            width: box.width - 2 * box.pad
            spacing: 4
            Heading { id: hint; text: "Move & Resize"; width: parent.width; elide: Text.ElideRight }
            Row {
                spacing: 4
                Tile { layout: "left"; symbol: "tile-left"; tip: "Left" }
                Tile { layout: "right"; symbol: "tile-right"; tip: "Right" }
                Tile { layout: "top"; symbol: "tile-top"; tip: "Top" }
                Tile { layout: "bottom"; symbol: "tile-bottom"; tip: "Bottom" }
            }
            Row {
                spacing: 4
                Tile { layout: "top-left"; symbol: "tile-top-left"; tip: "Top Left" }
                Tile { layout: "top-right"; symbol: "tile-top-right"; tip: "Top Right" }
                Tile { layout: "bottom-left"; symbol: "tile-bottom-left"; tip: "Bottom Left" }
                Tile { layout: "bottom-right"; symbol: "tile-bottom-right"; tip: "Bottom Right" }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.separator }
            MenuRow { text: "Fill"; command: "gg-tile fill" }
            MenuRow { text: "Center"; command: "gg-tile center" }
            MenuRow { text: "Return to Previous Size"; command: "gg-tile restore" }
            Rectangle { width: parent.width; height: 1; color: Theme.separator }
            MenuRow { text: "Enter Full Screen"; command: "hyprctl dispatch fullscreen 0" }
        }
        HoverHandler { onHoveredChanged: if (!hovered) hint.text = "Move & Resize" }
    }
}
