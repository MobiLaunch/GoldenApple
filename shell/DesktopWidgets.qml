// Desktop widgets: lightweight, live shell widgets that sit above the wallpaper.
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"

PanelWindow {
    id: board
    property bool editMode: false
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "gg-widgets"
    color: "transparent"
    mask: Region {}
    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property var player: Mpris.players.values.length ? Mpris.players.values[0] : null

    Item {
        id: widgets; anchors.fill: parent
        component Widget: Glass { variant: "clear";
            property point home
            tint: Theme.dark ? "#6b24262d" : "#72ffffff"
            MouseArea {
                anchors.fill: parent
                enabled: false
                drag.target: parent
                drag.minimumX: 12; drag.maximumX: widgets.width - parent.width - 12
                drag.minimumY: 42; drag.maximumY: widgets.height - parent.height - 90
            }
        }
        Widget {
            x: 28; y: 64; width: 250; height: 128; radius: 28
            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 1
                Text { text: Qt.formatDate(clock.date, "dddd"); color: Theme.accent; font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold } }
                Text { text: Qt.formatDate(clock.date, "MMMM d"); color: Theme.label; font { family: Theme.fontUi; pixelSize: 27; weight: Font.DemiBold } }
                Text { text: Qt.formatTime(clock.date, "h:mm"); color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 21 } }
            }
        }
        Widget {
            x: 28; y: 208; width: 250; height: 128; radius: 28
            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 7
                Text { text: "Now Playing"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                Text { width: parent.width; text: board.player?.trackTitle || "Nothing Playing"; elide: Text.ElideRight; color: Theme.label; font { family: Theme.fontUi; pixelSize: 18; weight: Font.DemiBold } }
                Text { width: parent.width; text: board.player?.trackArtist || ""; elide: Text.ElideRight; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 14 } }
            }
        }
    }
}
